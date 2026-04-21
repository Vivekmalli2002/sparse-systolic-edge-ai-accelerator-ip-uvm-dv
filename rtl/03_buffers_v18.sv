// =============================================================================
// File: 03_buffers_v18.sv
// Description: V18 Buffer subsystem for AXI4-Stream flow control
//              - Skid buffers for elastic pipeline
//              - Credit-based flow control
//              - Synchronous FIFOs with FWFT
// Version: 18.0
// =============================================================================

`timescale 1ns/1ps

// =============================================================================
// MODULE: skid_buffer_v18
// Description: 2-entry elastic buffer for AXI4-Stream backpressure absorption
//              Maintains full throughput when downstream stalls briefly
// =============================================================================
module skid_buffer_v18 #(
    parameter int DATA_WIDTH = 64
)(
    input  logic                    clk,
    input  logic                    rst_n,
    
    // Input interface (slave)
    input  logic [DATA_WIDTH-1:0]  s_data,
    input  logic                   s_valid,
    output logic                   s_ready,
    
    // Output interface (master)
    output logic [DATA_WIDTH-1:0]  m_data,
    output logic                   m_valid,
    input  logic                   m_ready
);

    // Skid register
    logic [DATA_WIDTH-1:0] skid_data;
    logic                  skid_valid;
    
    // Control signals
    logic use_skid;
    logic load_skid;
    
    // Output selection
    assign m_data  = use_skid ? skid_data : s_data;
    assign m_valid = use_skid ? skid_valid : s_valid;
    
    // Ready when skid is empty or will be emptied this cycle
    assign s_ready = !skid_valid || (m_ready && use_skid);
    
    // Load skid when input valid, we're ready, but output not ready
    assign load_skid = s_valid && s_ready && !m_ready && !use_skid;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            skid_data  <= '0;
            skid_valid <= 1'b0;
            use_skid   <= 1'b0;
        end else begin
            if (load_skid) begin
                // Stash incoming data in skid register
                skid_data  <= s_data;
                skid_valid <= 1'b1;
                use_skid   <= 1'b1;
            end else if (use_skid && m_ready) begin
                // Drain skid register
                skid_valid <= 1'b0;
                use_skid   <= 1'b0;
            end
        end
    end

endmodule


// =============================================================================
// MODULE: credit_counter_v18
// Description: Credit-based flow control for AXI4-Stream
//              Tracks available slots in downstream FIFO
// =============================================================================
module credit_counter_v18 #(
    parameter int MAX_CREDITS  = 14,
    parameter int CREDIT_WIDTH = $clog2(MAX_CREDITS + 1)
)(
    input  logic                      clk,
    input  logic                      rst_n,
    input  logic                      clear,
    
    // Credit management
    input  logic                      credit_consume,  // Sending data (use credit)
    input  logic                      credit_return,   // Data consumed downstream (return credit)
    input  logic [CREDIT_WIDTH-1:0]   credit_init,     // Initial credit value
    input  logic                      credit_reload,   // Reload to init value
    
    // Status
    output logic [CREDIT_WIDTH-1:0]   credits_available,
    output logic                      has_credit,
    output logic                      credit_empty,
    output logic                      credit_full
);

    logic [CREDIT_WIDTH-1:0] credit_count;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            credit_count <= MAX_CREDITS[CREDIT_WIDTH-1:0];
        end else if (clear || credit_reload) begin
            credit_count <= credit_init;
        end else begin
            case ({credit_consume, credit_return})
                2'b10: begin  // Consume only
                    if (credit_count > 0)
                        credit_count <= credit_count - 1;
                end
                2'b01: begin  // Return only
                    if (credit_count < MAX_CREDITS)
                        credit_count <= credit_count + 1;
                end
                2'b11: begin  // Both - no change
                    credit_count <= credit_count;
                end
                default: begin
                    credit_count <= credit_count;
                end
            endcase
        end
    end
    
    assign credits_available = credit_count;
    assign has_credit        = (credit_count > 0);
    assign credit_empty      = (credit_count == 0);
    assign credit_full       = (credit_count == MAX_CREDITS);

endmodule


// =============================================================================
// MODULE: sync_fifo_v18
// Description: Synchronous FIFO with First-Word-Fall-Through (FWFT)
//              Supports almost_full/almost_empty thresholds
// =============================================================================
module sync_fifo_v18 #(
    parameter int WIDTH        = 64,
    parameter int DEPTH        = 16,
    parameter int ALMOST_FULL  = 2,   // Threshold from full
    parameter int ALMOST_EMPTY = 2,   // Threshold from empty
    parameter bit FWFT         = 1    // First-Word-Fall-Through mode
)(
    input  logic                      clk,
    input  logic                      rst_n,
    input  logic                      clear,
    
    // Write interface
    input  logic                      push,
    input  logic [WIDTH-1:0]          din,
    output logic                      full,
    output logic                      almost_full,
    
    // Read interface
    input  logic                      pop,
    output logic [WIDTH-1:0]          dout,
    output logic                      empty,
    output logic                      almost_empty,
    output logic                      valid,
    
    // Status
    output logic [$clog2(DEPTH+1)-1:0] level,
    output logic                      overflow,
    output logic                      underflow
);

    localparam int PTR_W = $clog2(DEPTH);
    localparam int CNT_W = $clog2(DEPTH + 1);

    // Memory
    logic [WIDTH-1:0] mem [DEPTH];
    
    // Pointers (extra bit for wrap detection)
    logic [PTR_W:0] wr_ptr;
    logic [PTR_W:0] rd_ptr;
    
    // Count
    logic [CNT_W-1:0] count;
    assign count = wr_ptr - rd_ptr;
    assign level = count;

    // Status flags
    assign empty        = (count == 0);
    assign full         = (count == DEPTH);
    assign almost_empty = (count <= ALMOST_EMPTY);
    assign almost_full  = (count >= DEPTH - ALMOST_FULL);

    // Write logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_ptr   <= '0;
            overflow <= 1'b0;
        end else if (clear) begin
            wr_ptr   <= '0;
            overflow <= 1'b0;
        end else begin
            overflow <= 1'b0;
            if (push) begin
                if (!full) begin
                    mem[wr_ptr[PTR_W-1:0]] <= din;
                    wr_ptr <= wr_ptr + 1;
                end else begin
                    overflow <= 1'b1;
                end
            end
        end
    end

    // Read logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_ptr    <= '0;
            underflow <= 1'b0;
        end else if (clear) begin
            rd_ptr    <= '0;
            underflow <= 1'b0;
        end else begin
            underflow <= 1'b0;
            if (pop) begin
                if (!empty) begin
                    rd_ptr <= rd_ptr + 1;
                end else begin
                    underflow <= 1'b1;
                end
            end
        end
    end

    // Output
    generate
        if (FWFT) begin : gen_fwft
            // Combinational read - data available immediately
            assign dout  = mem[rd_ptr[PTR_W-1:0]];
            assign valid = !empty;
        end else begin : gen_std
            // Registered read - 1 cycle latency
            logic [WIDTH-1:0] dout_reg;
            logic             valid_reg;
            
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    dout_reg  <= '0;
                    valid_reg <= 1'b0;
                end else if (clear) begin
                    dout_reg  <= '0;
                    valid_reg <= 1'b0;
                end else begin
                    valid_reg <= 1'b0;
                    if (pop && !empty) begin
                        dout_reg  <= mem[rd_ptr[PTR_W-1:0]];
                        valid_reg <= 1'b1;
                    end
                end
            end
            
            assign dout  = dout_reg;
            assign valid = valid_reg;
        end
    endgenerate

endmodule


// =============================================================================
// MODULE: axis_data_fifo_v18
// Description: AXI4-Stream FIFO with full signal bundle support
//              Includes TDATA, TKEEP, TLAST, TUSER
// =============================================================================
module axis_data_fifo_v18
    import accel_pkg_v18::*;
#(
    parameter int DEPTH       = 16,
    parameter int DATA_WIDTH  = AXIS_DATA_WIDTH,
    parameter int USER_WIDTH  = AXIS_USER_WIDTH
)(
    input  logic                      clk,
    input  logic                      rst_n,
    input  logic                      clear,
    
    // AXI4-Stream Slave (input)
    input  logic [DATA_WIDTH-1:0]     s_axis_tdata,
    input  logic [DATA_WIDTH/8-1:0]   s_axis_tkeep,
    input  logic                      s_axis_tlast,
    input  logic [USER_WIDTH-1:0]     s_axis_tuser,
    input  logic                      s_axis_tvalid,
    output logic                      s_axis_tready,
    
    // AXI4-Stream Master (output)
    output logic [DATA_WIDTH-1:0]     m_axis_tdata,
    output logic [DATA_WIDTH/8-1:0]   m_axis_tkeep,
    output logic                      m_axis_tlast,
    output logic [USER_WIDTH-1:0]     m_axis_tuser,
    output logic                      m_axis_tvalid,
    input  logic                      m_axis_tready,
    
    // Status
    output logic [$clog2(DEPTH+1)-1:0] level,
    output logic                      empty,
    output logic                      full,
    output logic                      almost_full
);

    // Pack all AXIS signals into single FIFO entry
    localparam int KEEP_WIDTH = DATA_WIDTH / 8;
    localparam int ENTRY_WIDTH = DATA_WIDTH + KEEP_WIDTH + 1 + USER_WIDTH;
    
    logic [ENTRY_WIDTH-1:0] fifo_din;
    logic [ENTRY_WIDTH-1:0] fifo_dout;
    logic fifo_push, fifo_pop;
    logic fifo_valid;
    
    // Pack input
    assign fifo_din = {s_axis_tuser, s_axis_tlast, s_axis_tkeep, s_axis_tdata};
    
    // Unpack output
    assign m_axis_tdata = fifo_dout[DATA_WIDTH-1:0];
    assign m_axis_tkeep = fifo_dout[DATA_WIDTH +: KEEP_WIDTH];
    assign m_axis_tlast = fifo_dout[DATA_WIDTH + KEEP_WIDTH];
    assign m_axis_tuser = fifo_dout[DATA_WIDTH + KEEP_WIDTH + 1 +: USER_WIDTH];
    
    // Control
    assign fifo_push = s_axis_tvalid && s_axis_tready;
    assign fifo_pop  = m_axis_tvalid && m_axis_tready;
    assign s_axis_tready = !full;
    assign m_axis_tvalid = fifo_valid;
    
    sync_fifo_v18 #(
        .WIDTH       (ENTRY_WIDTH),
        .DEPTH       (DEPTH),
        .ALMOST_FULL (2),
        .ALMOST_EMPTY(2),
        .FWFT        (1)
    ) u_fifo (
        .clk         (clk),
        .rst_n       (rst_n),
        .clear       (clear),
        .push        (fifo_push),
        .din         (fifo_din),
        .full        (full),
        .almost_full (almost_full),
        .pop         (fifo_pop),
        .dout        (fifo_dout),
        .empty       (empty),
        .almost_empty(),
        .valid       (fifo_valid),
        .level       (level),
        .overflow    (),
        .underflow   ()
    );

endmodule


// =============================================================================
// MODULE: output_collector_fifo_v18
// Description: Collects array output columns into FIFO for result TX
//              Handles column-wise valid signals from deskew buffer
// =============================================================================
module output_collector_fifo_v18
    import accel_pkg_v18::*;
#(
    parameter int DEPTH  = OUTPUT_FIFO_DEPTH,
    parameter int DATA_W = ACC_WIDTH,
    parameter int COLS_P = COLS
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          clear,
    
    // Input from deskew buffer
    input  logic signed [DATA_W-1:0]      data_in     [COLS_P],
    input  logic [COLS_P-1:0]             valid_in,
    output logic                          ready_out,
    
    // Output to result TX
    output logic signed [DATA_W-1:0]      data_out    [COLS_P],
    output logic                          valid_out,
    input  logic                          read_en,
    
    // Status
    output logic                          empty,
    output logic                          full,
    output logic                          almost_full,
    output logic [$clog2(DEPTH+1)-1:0]    level,
    output logic                          overflow_err,
    output logic                          underflow_err
);

    // Pack columns into single FIFO entry
    localparam int ENTRY_W = DATA_W * COLS_P;
    
    logic [ENTRY_W-1:0] din_packed;
    logic [ENTRY_W-1:0] dout_packed;
    
    // Pack input columns
    generate
        for (genvar c = 0; c < COLS_P; c++) begin : gen_pack
            assign din_packed[c*DATA_W +: DATA_W] = data_in[c];
            assign data_out[c] = dout_packed[c*DATA_W +: DATA_W];
        end
    endgenerate
    
    // Push when all columns valid (aligned output from deskew)
    logic push_valid;
    assign push_valid = &valid_in;  // All columns must be valid
    
    sync_fifo_v18 #(
        .WIDTH       (ENTRY_W),
        .DEPTH       (DEPTH),
        .ALMOST_FULL (2),
        .ALMOST_EMPTY(1),
        .FWFT        (1)
    ) u_fifo (
        .clk         (clk),
        .rst_n       (rst_n),
        .clear       (clear),
        .push        (push_valid && ready_out),
        .din         (din_packed),
        .full        (full),
        .almost_full (almost_full),
        .pop         (read_en && !empty),
        .dout        (dout_packed),
        .empty       (empty),
        .almost_empty(),
        .valid       (valid_out),
        .level       (level),
        .overflow    (overflow_err),
        .underflow   (underflow_err)
    );
    
    assign ready_out = !full;

endmodule


// =============================================================================
// MODULE: weight_tile_buffer_v18
// Description: Tile-based weight buffer for systolic array loading
//              Stores complete weight tiles (ROWS x COLS weights)
//              Supports streaming from AXI4-Stream interface
// =============================================================================
module weight_tile_buffer_v18
    import accel_pkg_v18::*;
#(
    parameter int TILE_DEPTH = 4,    // Number of weight tiles
    parameter int ROWS_P     = ROWS,
    parameter int COLS_P     = COLS,
    parameter int WGT_PKT_W  = WGT_PKT_WIDTH
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          clear,
    
    // Write interface (from AXIS weight RX)
    input  logic                          wr_start,     // Start new tile
    input  logic                          wr_valid,     // Row data valid
    input  logic [WGT_PKT_W-1:0]          wr_data [COLS_P],  // Weight row
    input  logic [COLS_P-1:0]             wr_parity,
    output logic                          wr_ready,
    output logic                          wr_done,      // Tile complete
    
    // Read interface (to systolic array)
    input  logic                          rd_start,     // Start reading tile
    input  logic                          rd_next_row,  // Advance to next row
    output logic [WGT_PKT_W-1:0]          rd_data [COLS_P],
    output logic [COLS_P-1:0]             rd_parity,
    output logic [$clog2(ROWS_P)-1:0]     rd_row,
    output logic                          rd_valid,
    output logic                          rd_last_row,
    input  logic                          rd_done,      // Tile consumed
    
    // Status
    output logic                          can_accept_tile,
    output logic                          has_tile_ready,
    output logic [$clog2(TILE_DEPTH+1)-1:0] tile_count,
    output logic                          fifo_full,
    output logic                          fifo_empty
);

    localparam int TILE_WORDS = ROWS_P;
    localparam int TOTAL_WORDS = TILE_DEPTH * TILE_WORDS;
    localparam int ROW_WIDTH = WGT_PKT_W * COLS_P;
    
    // Storage
    logic [ROW_WIDTH-1:0] wgt_mem [TOTAL_WORDS];
    logic [COLS_P-1:0]    par_mem [TOTAL_WORDS];
    
    // Write state machine
    typedef enum logic [1:0] {W_IDLE, W_LOADING, W_COMMIT} wstate_t;
    wstate_t wstate;
    
    logic [$clog2(TILE_DEPTH)-1:0]   wr_tile_ptr;
    logic [$clog2(ROWS_P)-1:0]       wr_row_cnt;
    logic [$clog2(TILE_DEPTH+1)-1:0] tile_cnt;
    
    // Read state machine
    typedef enum logic [1:0] {R_IDLE, R_STREAMING, R_DONE} rstate_t;
    rstate_t rstate;
    
    logic [$clog2(TILE_DEPTH)-1:0] rd_tile_ptr;
    logic [$clog2(ROWS_P)-1:0]     rd_row_cnt;
    
    // Status signals
    assign tile_count      = tile_cnt;
    assign can_accept_tile = (tile_cnt < TILE_DEPTH);
    assign has_tile_ready  = (tile_cnt > 0);
    assign fifo_full       = (tile_cnt == TILE_DEPTH);
    assign fifo_empty      = (tile_cnt == 0);
    assign wr_ready = can_accept_tile && (wstate != W_COMMIT);
    
    // Pack write data
    logic [ROW_WIDTH-1:0] wr_data_packed;
    generate
        for (genvar c = 0; c < COLS_P; c++) begin : gen_pack_wr
            assign wr_data_packed[c*WGT_PKT_W +: WGT_PKT_W] = wr_data[c];
        end
    endgenerate
    
    // Write logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wstate      <= W_IDLE;
            wr_tile_ptr <= '0;
            wr_row_cnt  <= '0;
            wr_done     <= 1'b0;
        end else if (clear) begin
            wstate      <= W_IDLE;
            wr_tile_ptr <= '0;
            wr_row_cnt  <= '0;
            wr_done     <= 1'b0;
        end else begin
            wr_done <= 1'b0;
            
            case (wstate)
                W_IDLE: begin
                    wr_row_cnt <= '0;
                    if (wr_start && can_accept_tile) begin
                        wstate <= W_LOADING;
                        // axis_weight_rx asserts wr_start and wr_valid on the
                        // same cycle (first beat).  Capture row 0 here so it is
                        // not lost when W_LOADING begins next cycle.
                        if (wr_valid) begin
                            wgt_mem[wr_tile_ptr * TILE_WORDS] <= wr_data_packed;
                            par_mem[wr_tile_ptr * TILE_WORDS] <= wr_parity;
                            wr_row_cnt <= 'd1;
                        end
                    end
                end
                
                W_LOADING: begin
                    if (wr_valid && can_accept_tile) begin
                        wgt_mem[wr_tile_ptr * TILE_WORDS + wr_row_cnt] <= wr_data_packed;
                        par_mem[wr_tile_ptr * TILE_WORDS + wr_row_cnt] <= wr_parity;
                        
                        if (wr_row_cnt == ROWS_P - 1) begin
                            wstate <= W_COMMIT;
                            wr_row_cnt <= '0;
                        end else begin
                            wr_row_cnt <= wr_row_cnt + 1;
                        end
                    end
                end
                
                W_COMMIT: begin
                    wr_tile_ptr <= (wr_tile_ptr + 1) % TILE_DEPTH;
                    wr_done <= 1'b1;
                    wstate <= W_IDLE;
                end
                
                default: wstate <= W_IDLE;
            endcase
        end
    end
    
    // Read logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rstate      <= R_IDLE;
            rd_tile_ptr <= '0;
            rd_row_cnt  <= '0;
        end else if (clear) begin
            rstate      <= R_IDLE;
            rd_tile_ptr <= '0;
            rd_row_cnt  <= '0;
        end else begin
            case (rstate)
                R_IDLE: begin
                    rd_row_cnt <= '0;
                    if (rd_start && has_tile_ready)
                        rstate <= R_STREAMING;
                end
                
                R_STREAMING: begin
                    if (rd_next_row) begin
                        if (rd_row_cnt == ROWS_P - 1) begin
                            if (rd_done) begin
                                rd_tile_ptr <= (rd_tile_ptr + 1) % TILE_DEPTH;
                                rd_row_cnt <= '0;
                                rstate <= R_IDLE;
                            end else begin
                                rstate <= R_DONE;
                            end
                        end else begin
                            rd_row_cnt <= rd_row_cnt + 1;
                        end
                    end
                end
                
                R_DONE: begin
                    if (rd_done) begin
                        rd_tile_ptr <= (rd_tile_ptr + 1) % TILE_DEPTH;
                        rd_row_cnt <= '0;
                        rstate <= R_IDLE;
                    end
                end
                
                default: rstate <= R_IDLE;
            endcase
        end
    end
    
    // Read data unpacking
    logic [ROW_WIDTH-1:0] rd_data_packed;
    assign rd_data_packed = wgt_mem[rd_tile_ptr * TILE_WORDS + rd_row_cnt];
    assign rd_parity      = par_mem[rd_tile_ptr * TILE_WORDS + rd_row_cnt];
    
    generate
        for (genvar c = 0; c < COLS_P; c++) begin : gen_unpack_rd
            assign rd_data[c] = rd_data_packed[c*WGT_PKT_W +: WGT_PKT_W];
        end
    endgenerate
    
    assign rd_row      = rd_row_cnt;
    assign rd_valid    = (rstate == R_STREAMING);
    assign rd_last_row = (rd_row_cnt == ROWS_P - 1);
    
    // Tile count management
    logic read_completed;
    assign read_completed = (rstate == R_DONE && rd_done) ||
                           (rstate == R_STREAMING && rd_next_row && rd_row_cnt == ROWS_P - 1 && rd_done);
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tile_cnt <= '0;
        end else if (clear) begin
            tile_cnt <= '0;
        end else begin
            case ({wstate == W_COMMIT, read_completed})
                2'b10:   tile_cnt <= tile_cnt + 1;
                2'b01:   tile_cnt <= (tile_cnt > 0) ? tile_cnt - 1 : '0;
                default: tile_cnt <= tile_cnt;
            endcase
        end
    end

endmodule