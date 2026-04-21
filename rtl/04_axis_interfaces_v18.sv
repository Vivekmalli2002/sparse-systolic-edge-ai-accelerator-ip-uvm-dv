// =============================================================================
// File: 04_axis_interfaces_v18.sv
// Description: V18.4 AXI4-Stream Interface modules (128-bit)
//              - Weight RX with multi-beat row support (6 weights per beat)
//              - Activation RX with skid buffer (16 activations per beat)
//              - Result TX with round-robin drain (4 results per beat)
// Version: 18.4 - Widened to 128-bit for 2x throughput
// =============================================================================

`timescale 1ns/1ps

// =============================================================================
// MODULE: axis_weight_rx_v18
// Description: AXI4-Stream weight receiver with multi-beat per row support
//              For 128-bit interface with 20-bit packets: 6 weights per beat
//              COLS_P=8:  2 beats per row (6+2)
//              COLS_P=32: 6 beats per row (6*5+2)
// =============================================================================
module axis_weight_rx_v18
    import accel_pkg_v18::*;
#(
    parameter int FIFO_DEPTH = WEIGHT_FIFO_DEPTH,
    parameter int ROWS_P     = ROWS,
    parameter int COLS_P     = COLS
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          enable,
    input  logic                          clear,
    
    // AXI4-Stream Slave Interface (from external) - 128-bit
    input  logic [AXIS_DATA_WIDTH-1:0]    s_axis_tdata,
    input  logic [AXIS_DATA_WIDTH/8-1:0]  s_axis_tkeep,
    input  logic                          s_axis_tlast,
    input  logic [AXIS_USER_WIDTH-1:0]    s_axis_tuser,
    input  logic                          s_axis_tvalid,
    output logic                          s_axis_tready,
    
    // Weight output to tile buffer
    output logic                          wgt_tile_start,
    output logic                          wgt_row_valid,
    output logic [WGT_PKT_WIDTH-1:0]      wgt_data [COLS_P],
    output logic [COLS_P-1:0]             wgt_parity,
    output logic                          wgt_tile_done,
    input  logic                          wgt_tile_ready,
    
    // Sparsity metadata (from TUSER)
    output sparsity_mode_e                sparsity_mode,
    output logic [3:0]                    sparse_mask,
    
    // Status
    output logic                          rx_active,
    output logic [$clog2(ROWS_P)-1:0]     rx_row_count,
    output logic                          rx_error
);

    // =========================================================================
    // Parameters for multi-beat packing (128-bit interface)
    // =========================================================================
    localparam int PKTS_PER_BEAT = AXIS_DATA_WIDTH / WGT_PKT_WIDTH;  // 128/20 = 6
    localparam int BEATS_PER_ROW = (COLS_P + PKTS_PER_BEAT - 1) / PKTS_PER_BEAT;
    
    // =========================================================================
    // State Machine
    // =========================================================================
    typedef enum logic [1:0] {
        RX_IDLE,
        RX_RECEIVING,
        RX_TILE_DONE
    } rx_state_t;
    
    rx_state_t state;
    
    // Counters
    logic [$clog2(ROWS_P)-1:0] row_cnt;
    logic [$clog2(BEATS_PER_ROW+1)-1:0] beat_cnt;
    
    // Weight register bank - holds all columns for current row
    logic [WGT_PKT_WIDTH-1:0] wgt_reg [COLS_P];
    
    // TUSER decoding
    weight_tuser_t tuser_decoded;
    assign tuser_decoded = s_axis_tuser;
    
    // Extract sparsity info
    assign sparsity_mode = sparsity_mode_e'(tuser_decoded.sparsity_mode);
    assign sparse_mask   = tuser_decoded.sparse_mask;
    
    // Ready when enabled and tile buffer can accept
    assign s_axis_tready = enable && (state == RX_IDLE || state == RX_RECEIVING) && wgt_tile_ready;
    
    // Status
    assign rx_active    = (state == RX_RECEIVING);
    assign rx_row_count = row_cnt;
    
    // Handshake detection
    logic handshake;
    assign handshake = s_axis_tvalid && s_axis_tready;
    
    // =========================================================================
    // Data Path - Capture weights from each beat into register bank
    // 128-bit interface: 6 weight packets per beat
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int c = 0; c < COLS_P; c++)
                wgt_reg[c] <= '0;
        end else if (clear) begin
            for (int c = 0; c < COLS_P; c++)
                wgt_reg[c] <= '0;
        end else if (handshake) begin
            // Extract packets from current beat and store in appropriate columns
            // 128-bit / 20-bit = 6 packets per beat
            for (int p = 0; p < PKTS_PER_BEAT; p++) begin
                automatic int col_idx = beat_cnt * PKTS_PER_BEAT + p;
                if (col_idx < COLS_P) begin
                    wgt_reg[col_idx] <= s_axis_tdata[p * WGT_PKT_WIDTH +: WGT_PKT_WIDTH];
                end
            end
        end
    end
    
    // Output weight data from register bank
    assign wgt_data = wgt_reg;
    
    // Parity generation
    generate
        for (genvar c = 0; c < COLS_P; c++) begin : gen_parity
            assign wgt_parity[c] = ^wgt_reg[c];
        end
    endgenerate
    
    // =========================================================================
    // Control FSM - handles multi-beat rows
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= RX_IDLE;
            row_cnt        <= '0;
            beat_cnt       <= '0;
            wgt_tile_start <= 1'b0;
            wgt_row_valid  <= 1'b0;
            wgt_tile_done  <= 1'b0;
            rx_error       <= 1'b0;
        end else if (clear) begin
            state          <= RX_IDLE;
            row_cnt        <= '0;
            beat_cnt       <= '0;
            wgt_tile_start <= 1'b0;
            wgt_row_valid  <= 1'b0;
            wgt_tile_done  <= 1'b0;
            rx_error       <= 1'b0;
        end else begin
            // Default: clear pulse signals
            wgt_tile_start <= 1'b0;
            wgt_row_valid  <= 1'b0;
            wgt_tile_done  <= 1'b0;
            
            case (state)
                RX_IDLE: begin
                    row_cnt  <= '0;
                    beat_cnt <= '0;
                    if (enable && handshake) begin
                        wgt_tile_start <= 1'b1;
                        beat_cnt <= 'd1;
                        
                        if (BEATS_PER_ROW == 1) begin
                            // Single beat per row - row complete
                            wgt_row_valid <= 1'b1;
                            row_cnt <= 'd1;
                            if (s_axis_tlast) begin
                                wgt_tile_done <= 1'b1;
                                state <= RX_TILE_DONE;
                            end else begin
                                state <= RX_RECEIVING;
                            end
                        end else begin
                            // Multi-beat per row - need more beats
                            state <= RX_RECEIVING;
                        end
                    end
                end
                
                RX_RECEIVING: begin
                    if (handshake) begin
                        if (beat_cnt == BEATS_PER_ROW - 1) begin
                            // Last beat of current row
                            wgt_row_valid <= 1'b1;
                            beat_cnt <= '0;
                            
                            if (row_cnt == ROWS_P - 1 || s_axis_tlast) begin
                                // Tile complete
                                wgt_tile_done <= 1'b1;
                                row_cnt <= '0;
                                state <= RX_TILE_DONE;
                            end else begin
                                row_cnt <= row_cnt + 1;
                            end
                        end else begin
                            // More beats needed for current row
                            beat_cnt <= beat_cnt + 1;
                        end
                    end
                end
                
                RX_TILE_DONE: begin
                    // Wait one cycle then return to idle
                    state <= RX_IDLE;
                end
                
                default: state <= RX_IDLE;
            endcase
        end
    end

endmodule


// =============================================================================
// MODULE: axis_activation_rx_v18
// Description: AXI4-Stream activation receiver with skid buffer (128-bit)
//              Feeds activations to systolic array skew buffer
//              Simplified pass-through: outputs first 32-bit packet from 128-bit beat
// =============================================================================
module axis_activation_rx_v18
    import accel_pkg_v18::*;
#(
    parameter int ROWS_P = ROWS
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          enable,
    input  logic                          clear,
    
    // AXI4-Stream Slave Interface - 128-bit
    input  logic [AXIS_DATA_WIDTH-1:0]    s_axis_tdata,
    input  logic [AXIS_DATA_WIDTH/8-1:0]  s_axis_tkeep,
    input  logic                          s_axis_tlast,
    input  logic                          s_axis_tvalid,
    output logic                          s_axis_tready,
    
    // Activation output (still 32-bit packets internally)
    output logic [ACT_PKT_WIDTH-1:0]      act_data,
    output logic                          act_valid,
    input  logic                          act_ready,
    output logic                          act_last,
    
    // Status
    output logic                          rx_active,
    output logic                          rx_done
);

    // =========================================================================
    // Skid Buffer for backpressure handling
    // Simple pass-through: use first 32-bit packet from 128-bit beat
    // =========================================================================
    logic [ACT_PKT_WIDTH-1:0] skid_data;
    logic                      skid_last;
    logic                      skid_valid;
    logic                      use_skid;
    
    // Ready when enabled and either no skid data or downstream ready
    assign s_axis_tready = enable && (!skid_valid || (act_ready && use_skid));
    
    // Skid buffer capture
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            skid_data  <= '0;
            skid_last  <= 1'b0;
            skid_valid <= 1'b0;
        end else if (clear) begin
            skid_data  <= '0;
            skid_last  <= 1'b0;
            skid_valid <= 1'b0;
        end else begin
            if (s_axis_tvalid && s_axis_tready && !act_ready) begin
                // Capture in skid buffer when downstream not ready
                skid_data  <= s_axis_tdata[ACT_PKT_WIDTH-1:0];
                skid_last  <= s_axis_tlast;
                skid_valid <= 1'b1;
            end else if (act_ready && skid_valid) begin
                // Drain skid buffer
                skid_valid <= 1'b0;
            end
        end
    end
    
    // Select between direct path and skid buffer
    assign use_skid  = skid_valid;
    assign act_data  = use_skid ? skid_data : s_axis_tdata[ACT_PKT_WIDTH-1:0];
    assign act_valid = enable && (use_skid ? skid_valid : s_axis_tvalid);
    assign act_last  = use_skid ? skid_last : s_axis_tlast;
    
    // Status
    assign rx_active = s_axis_tvalid || skid_valid;
    
    // Done pulse on tlast
    logic last_seen;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_seen <= 1'b0;
            rx_done   <= 1'b0;
        end else if (clear) begin
            last_seen <= 1'b0;
            rx_done   <= 1'b0;
        end else begin
            rx_done <= 1'b0;
            if (act_valid && act_ready && act_last && !last_seen) begin
                rx_done   <= 1'b1;
                last_seen <= 1'b1;
            end else if (!s_axis_tvalid && !skid_valid) begin
                last_seen <= 1'b0;
            end
        end
    end

endmodule


// =============================================================================
// MODULE: axis_result_tx_v18
// Description: AXI4-Stream result transmitter (128-bit)
//              Packs 4 × 32-bit results per 128-bit beat
//              Generates TLAST at end of drain sequence
// =============================================================================
module axis_result_tx_v18
    import accel_pkg_v18::*;
#(
    parameter int COLS_P = COLS
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          enable,
    input  logic                          clear,
    
    // AXI4-Stream Master Interface - 128-bit
    output logic [AXIS_DATA_WIDTH-1:0]    m_axis_tdata,
    output logic [AXIS_DATA_WIDTH/8-1:0]  m_axis_tkeep,
    output logic                          m_axis_tlast,
    output logic [AXIS_USER_WIDTH-1:0]    m_axis_tuser,
    output logic                          m_axis_tvalid,
    input  logic                          m_axis_tready,
    
    // Result input from output FIFO
    input  logic signed [ACC_WIDTH-1:0]   result_data [COLS_P],
    input  logic                          result_valid,
    output logic                          result_read,
    
    // Drain control
    input  logic                          drain_start,
    input  logic [15:0]                   drain_count,
    output logic                          drain_done,
    
    // Status
    output logic                          tx_active
);

    // =========================================================================
    // Parameters for 128-bit interface
    // =========================================================================
    localparam int RESULTS_PER_BEAT = AXIS_DATA_WIDTH / ACC_WIDTH;  // 128/32 = 4
    localparam int BEATS_PER_ROW = (COLS_P + RESULTS_PER_BEAT - 1) / RESULTS_PER_BEAT;
    
    // =========================================================================
    // State Machine
    // =========================================================================
    typedef enum logic [1:0] {
        TX_IDLE,
        TX_SEND,
        TX_DONE
    } tx_state_t;
    
    tx_state_t state;
    
    // Counters
    logic [$clog2(BEATS_PER_ROW+1)-1:0] beat_cnt;
    logic [15:0] row_cnt;
    
    // Result register - latch full row
    logic signed [ACC_WIDTH-1:0] result_reg [COLS_P];
    
    // Status
    assign tx_active   = (state != TX_IDLE);
    assign drain_done  = (state == TX_DONE);
    
    // =========================================================================
    // Data packing - 4 results per 128-bit beat
    // =========================================================================
    logic signed [ACC_WIDTH-1:0] result_0, result_1, result_2, result_3;
    logic [AXIS_DATA_WIDTH-1:0]  packed_data;
    int col_base;
    
    always_comb begin
        col_base = beat_cnt * RESULTS_PER_BEAT;
        result_0 = (col_base < COLS_P) ? result_reg[col_base] : '0;
        result_1 = (col_base + 1 < COLS_P) ? result_reg[col_base + 1] : '0;
        result_2 = (col_base + 2 < COLS_P) ? result_reg[col_base + 2] : '0;
        result_3 = (col_base + 3 < COLS_P) ? result_reg[col_base + 3] : '0;
        packed_data = {result_3, result_2, result_1, result_0};
    end
    
    // AXI-Stream outputs
    assign m_axis_tdata  = packed_data;
    assign m_axis_tkeep  = 16'hFFFF;  // All 16 bytes valid
    assign m_axis_tuser  = 8'h00;
    assign m_axis_tvalid = (state == TX_SEND);
    assign m_axis_tlast  = (state == TX_SEND) && 
                           (beat_cnt == BEATS_PER_ROW - 1) && 
                           (row_cnt == drain_count - 1);
    
    // Read from FIFO when entering new row
    assign result_read = (state == TX_SEND) && (beat_cnt == 0) && m_axis_tready && result_valid;
    
    // =========================================================================
    // Control FSM
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state    <= TX_IDLE;
            beat_cnt <= '0;
            row_cnt  <= '0;
            for (int c = 0; c < COLS_P; c++)
                result_reg[c] <= '0;
        end else if (clear) begin
            state    <= TX_IDLE;
            beat_cnt <= '0;
            row_cnt  <= '0;
            for (int c = 0; c < COLS_P; c++)
                result_reg[c] <= '0;
        end else begin
            case (state)
                TX_IDLE: begin
                    beat_cnt <= '0;
                    row_cnt  <= '0;
                    if (enable && drain_start && result_valid) begin
                        // Latch first row of results
                        for (int c = 0; c < COLS_P; c++)
                            result_reg[c] <= result_data[c];
                        state <= TX_SEND;
                    end
                end
                
                TX_SEND: begin
                    if (m_axis_tready) begin
                        if (beat_cnt == BEATS_PER_ROW - 1) begin
                            // End of row
                            beat_cnt <= '0;
                            if (row_cnt == drain_count - 1) begin
                                state <= TX_DONE;
                            end else begin
                                row_cnt <= row_cnt + 1;
                                // Latch next row
                                if (result_valid) begin
                                    for (int c = 0; c < COLS_P; c++)
                                        result_reg[c] <= result_data[c];
                                end
                            end
                        end else begin
                            beat_cnt <= beat_cnt + 1;
                        end
                    end
                end
                
                TX_DONE: begin
                    if (!drain_start) begin
                        state <= TX_IDLE;
                    end
                end
                
                default: state <= TX_IDLE;
            endcase
        end
    end

endmodule


// =============================================================================
// MODULE: axis_interface_wrapper_v18
// Description: Wrapper combining all AXIS interfaces for top-level integration
//              128-bit version
// =============================================================================
module axis_interface_wrapper_v18
    import accel_pkg_v18::*;
#(
    parameter int ROWS_P = ROWS,
    parameter int COLS_P = COLS
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          clear,
    
    // Global enable
    input  logic                          enable,
    
    // Weight AXIS Slave - 128-bit
    input  logic [AXIS_DATA_WIDTH-1:0]    s_axis_weight_tdata,
    input  logic [AXIS_DATA_WIDTH/8-1:0]  s_axis_weight_tkeep,
    input  logic                          s_axis_weight_tlast,
    input  logic [AXIS_USER_WIDTH-1:0]    s_axis_weight_tuser,
    input  logic                          s_axis_weight_tvalid,
    output logic                          s_axis_weight_tready,
    
    // Activation AXIS Slave - 128-bit
    input  logic [AXIS_DATA_WIDTH-1:0]    s_axis_act_tdata,
    input  logic [AXIS_DATA_WIDTH/8-1:0]  s_axis_act_tkeep,
    input  logic                          s_axis_act_tlast,
    input  logic                          s_axis_act_tvalid,
    output logic                          s_axis_act_tready,
    
    // Result AXIS Master - 128-bit
    output logic [AXIS_DATA_WIDTH-1:0]    m_axis_result_tdata,
    output logic [AXIS_DATA_WIDTH/8-1:0]  m_axis_result_tkeep,
    output logic                          m_axis_result_tlast,
    output logic [AXIS_USER_WIDTH-1:0]    m_axis_result_tuser,
    output logic                          m_axis_result_tvalid,
    input  logic                          m_axis_result_tready,
    
    // Internal interfaces to compute core
    output logic                          wgt_tile_start,
    output logic                          wgt_row_valid,
    output logic [WGT_PKT_WIDTH-1:0]      wgt_data [COLS_P],
    output logic [COLS_P-1:0]             wgt_parity,
    output logic                          wgt_tile_done,
    input  logic                          wgt_tile_ready,
    output sparsity_mode_e                sparsity_mode,
    
    output logic [ACT_PKT_WIDTH-1:0]      act_data,
    output logic                          act_valid,
    input  logic                          act_ready,
    output logic                          act_last,
    
    input  logic signed [ACC_WIDTH-1:0]   result_data [COLS_P],
    input  logic                          result_valid,
    output logic                          result_read,
    input  logic                          drain_start,
    input  logic [15:0]                   drain_count,
    output logic                          drain_done,
    
    // Status
    output logic                          weight_rx_active,
    output logic                          act_rx_active,
    output logic                          result_tx_active
);

    // =========================================================================
    // Weight RX (128-bit)
    // =========================================================================
    logic [3:0] sparse_mask_unused;
    logic       weight_rx_error;
    logic [$clog2(ROWS_P)-1:0] weight_rx_row;
    
    axis_weight_rx_v18 #(
        .ROWS_P(ROWS_P),
        .COLS_P(COLS_P)
    ) u_weight_rx (
        .clk            (clk),
        .rst_n          (rst_n),
        .enable         (enable),
        .clear          (clear),
        .s_axis_tdata   (s_axis_weight_tdata),
        .s_axis_tkeep   (s_axis_weight_tkeep),
        .s_axis_tlast   (s_axis_weight_tlast),
        .s_axis_tuser   (s_axis_weight_tuser),
        .s_axis_tvalid  (s_axis_weight_tvalid),
        .s_axis_tready  (s_axis_weight_tready),
        .wgt_tile_start (wgt_tile_start),
        .wgt_row_valid  (wgt_row_valid),
        .wgt_data       (wgt_data),
        .wgt_parity     (wgt_parity),
        .wgt_tile_done  (wgt_tile_done),
        .wgt_tile_ready (wgt_tile_ready),
        .sparsity_mode  (sparsity_mode),
        .sparse_mask    (sparse_mask_unused),
        .rx_active      (weight_rx_active),
        .rx_row_count   (weight_rx_row),
        .rx_error       (weight_rx_error)
    );

    // =========================================================================
    // Activation RX (128-bit)
    // =========================================================================
    logic act_rx_done;
    
    axis_activation_rx_v18 #(
        .ROWS_P(ROWS_P)
    ) u_act_rx (
        .clk           (clk),
        .rst_n         (rst_n),
        .enable        (enable),
        .clear         (clear),
        .s_axis_tdata  (s_axis_act_tdata),
        .s_axis_tkeep  (s_axis_act_tkeep),
        .s_axis_tlast  (s_axis_act_tlast),
        .s_axis_tvalid (s_axis_act_tvalid),
        .s_axis_tready (s_axis_act_tready),
        .act_data      (act_data),
        .act_valid     (act_valid),
        .act_ready     (act_ready),
        .act_last      (act_last),
        .rx_active     (act_rx_active),
        .rx_done       (act_rx_done)
    );

    // =========================================================================
    // Result TX (128-bit)
    // =========================================================================
    axis_result_tx_v18 #(
        .COLS_P(COLS_P)
    ) u_result_tx (
        .clk           (clk),
        .rst_n         (rst_n),
        .enable        (enable),
        .clear         (clear),
        .m_axis_tdata  (m_axis_result_tdata),
        .m_axis_tkeep  (m_axis_result_tkeep),
        .m_axis_tlast  (m_axis_result_tlast),
        .m_axis_tuser  (m_axis_result_tuser),
        .m_axis_tvalid (m_axis_result_tvalid),
        .m_axis_tready (m_axis_result_tready),
        .result_data   (result_data),
        .result_valid  (result_valid),
        .result_read   (result_read),
        .drain_start   (drain_start),
        .drain_count   (drain_count),
        .drain_done    (drain_done),
        .tx_active     (result_tx_active)
    );

endmodule