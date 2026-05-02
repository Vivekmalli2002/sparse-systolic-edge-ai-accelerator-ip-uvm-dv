// =============================================================================
// File: 05_control_v18.sv
// Description: V18.2 Control subsystem with Weight Reuse Support
// Version: 18.2 - Added act_tile_count for weight-stationary optimization
// =============================================================================
// Changes from V18.1:
//   - Added CSR_ACT_TILE_CFG register (0x0E4)
//   - Modified compute_controller FSM to skip weight reload when act_tile_cnt < act_tile_count
//   - Backwards compatible: default act_tile_count=1 preserves V18.1 behavior
// =============================================================================

`timescale 1ns/1ps

// =============================================================================
// MODULE: accel_csr_axil_v18
// Description: Control/Status Register block with AXI4-Lite interface
//              V18.2: Added act_tile_count output
// =============================================================================
module accel_csr_axil_v18
    import accel_pkg_v18::*;
#(
    parameter int ADDR_W = AXIL_ADDR_WIDTH,
    parameter int DATA_W = AXIL_DATA_WIDTH,
    parameter int ROWS_P = ROWS,
    parameter int COLS_P = COLS
)(
    input  logic                 clk,
    input  logic                 rst_n,
    
    // =========================================================================
    // AXI4-Lite Slave Interface
    // =========================================================================
    input  logic [ADDR_W-1:0]    s_axil_awaddr,
    input  logic [2:0]           s_axil_awprot,
    input  logic                 s_axil_awvalid,
    output logic                 s_axil_awready,
    
    input  logic [DATA_W-1:0]    s_axil_wdata,
    input  logic [DATA_W/8-1:0]  s_axil_wstrb,
    input  logic                 s_axil_wvalid,
    output logic                 s_axil_wready,
    
    output logic [1:0]           s_axil_bresp,
    output logic                 s_axil_bvalid,
    input  logic                 s_axil_bready,
    
    input  logic [ADDR_W-1:0]    s_axil_araddr,
    input  logic [2:0]           s_axil_arprot,
    input  logic                 s_axil_arvalid,
    output logic                 s_axil_arready,
    
    output logic [DATA_W-1:0]    s_axil_rdata,
    output logic [1:0]           s_axil_rresp,
    output logic                 s_axil_rvalid,
    input  logic                 s_axil_rready,
    
    // =========================================================================
    // Control Outputs
    // =========================================================================
    output logic                 ctrl_enable,
    output logic                 ctrl_start,
    output logic                 ctrl_soft_reset,
    output logic                 ctrl_abort,
    output logic                 ctrl_clear,
    output logic                 mode_dense,
    output sparsity_mode_e       sparsity_cfg,
    output activation_e          activation_fn,
    output logic [15:0]          tile_count,
    output logic [15:0]          vector_count,
    output logic [15:0]          act_tile_count,  // NEW for V18.2
    
    // =========================================================================
    // Post-Processing Configuration Outputs
    // =========================================================================
    output postproc_op_e                     pp_op_sel,
    output logic signed [PP_BIAS_WIDTH-1:0]  pp_bias [COLS_P],
    output logic signed [PP_SCALE_WIDTH-1:0] pp_scale,
    output logic [PP_SHIFT_WIDTH-1:0]        pp_shift,
    output logic                             pp_round_en,
    output logic                             pp_sat_en,
    output logic signed [ACC_WIDTH-1:0]      pp_sat_max,
    output logic signed [ACC_WIDTH-1:0]      pp_sat_min,
    
    // =========================================================================
    // Status Inputs
    // =========================================================================
    input  logic                 status_busy,
    input  logic                 status_done,
    input  compute_state_e       status_state,
    
    input  logic [4:0]           wfifo_level,
    input  logic                 wfifo_full,
    input  logic                 wfifo_empty,
    input  logic [4:0]           afifo_level,
    input  logic                 afifo_full,
    input  logic                 afifo_empty,
    input  logic [4:0]           rfifo_level,
    input  logic                 rfifo_full,
    input  logic                 rfifo_empty,
    
    input  logic [31:0]          perf_cycles,
    input  logic [31:0]          perf_stalls,
    input  logic [31:0]          perf_macs,
    input  logic [31:0]          perf_zero_weights,
    input  logic [31:0]          perf_zero_acts,
    
    output logic [7:0]           irq_enable,
    input  logic [7:0]           irq_status_in,
    output logic [7:0]           irq_clear,
    output logic                 irq_out
);

    // =========================================================================
    // Local Parameters
    // =========================================================================
    localparam int PP_OP_LSB       = 0;
    localparam int PP_OP_MSB       = 2;
    localparam int PP_ROUND_EN_BIT = 8;
    localparam int PP_SAT_EN_BIT   = 9;
    
    localparam logic [31:0] CAP1_VALUE = {16'(OUTPUT_FIFO_DEPTH), 8'(ACT_FIFO_DEPTH), 8'(WEIGHT_FIFO_DEPTH)};
    localparam logic [31:0] CAP2_VALUE = {24'b0, 4'b1111, 1'b1, 1'b1, 1'b1, 1'b1};

    // =========================================================================
    // AXI-Lite State Machine
    // =========================================================================
    typedef enum logic [1:0] {
        AXIL_IDLE,
        AXIL_WRITE,
        AXIL_READ,
        AXIL_RESP
    } axil_state_e;
    
    axil_state_e wr_state, rd_state;
    
    logic [ADDR_W-1:0] wr_addr_reg;
    logic [ADDR_W-1:0] rd_addr_reg;
    logic [DATA_W-1:0] wr_data_reg;
    logic [DATA_W/8-1:0] wr_strb_reg;

    // =========================================================================
    // Registers
    // =========================================================================
    logic [31:0] reg_ctrl;
    logic [31:0] reg_tile_cfg;
    logic [31:0] reg_sparsity_cfg;
    logic [31:0] reg_axis_ctrl;
    logic [7:0]  reg_irq_enable;
    logic [7:0]  reg_irq_status;
    
    // Post-processing registers
    logic [31:0] reg_pp_ctrl;
    logic [31:0] reg_pp_scale;
    logic [31:0] reg_pp_shift;
    logic [31:0] reg_pp_sat_max;
    logic [31:0] reg_pp_sat_min;
    logic [31:0] reg_pp_bias [8];  // Legacy 8 registers (16 biases)
    
    // V18.3: Scalable bias memory (supports all COLS_P biases)
    logic signed [PP_BIAS_WIDTH-1:0] bias_mem [COLS_P];
    logic [7:0] bias_wr_addr;  // Write address (0 to COLS_P-1)
    logic       use_scalable_bias;  // Flag: use scalable memory vs legacy CSRs
    
    // V18.2: Activation tile count register
    logic [31:0] reg_act_tile_cfg;
    
    // Self-clearing pulse registers
    logic start_pulse, reset_pulse, abort_pulse, clear_pulse;

    // =========================================================================
    // AXI-Lite Write State Machine
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_state     <= AXIL_IDLE;
            wr_addr_reg  <= '0;
            wr_data_reg  <= '0;
            wr_strb_reg  <= '0;
            s_axil_awready <= 1'b0;
            s_axil_wready  <= 1'b0;
            s_axil_bvalid  <= 1'b0;
            s_axil_bresp   <= AXIL_RESP_OKAY;
        end else begin
            case (wr_state)
                AXIL_IDLE: begin
                    s_axil_awready <= 1'b1;
                    s_axil_wready  <= 1'b1;
                    s_axil_bvalid  <= 1'b0;
                    
                    if (s_axil_awvalid && s_axil_awready) begin
                        wr_addr_reg <= s_axil_awaddr;
                        if (s_axil_wvalid && s_axil_wready) begin
                            wr_data_reg <= s_axil_wdata;
                            wr_strb_reg <= s_axil_wstrb;
                            s_axil_awready <= 1'b0;
                            s_axil_wready  <= 1'b0;
                            wr_state <= AXIL_WRITE;
                        end else begin
                            s_axil_awready <= 1'b0;
                            wr_state <= AXIL_WRITE;
                        end
                    end else if (s_axil_wvalid && s_axil_wready) begin
                        wr_data_reg <= s_axil_wdata;
                        wr_strb_reg <= s_axil_wstrb;
                        s_axil_wready <= 1'b0;
                    end
                end
                
                AXIL_WRITE: begin
                    if (s_axil_wvalid && s_axil_wready) begin
                        wr_data_reg <= s_axil_wdata;
                        wr_strb_reg <= s_axil_wstrb;
                        s_axil_wready <= 1'b0;
                    end

                    if (!s_axil_awready && !s_axil_wready) begin
                        s_axil_bvalid <= 1'b1;
                        
                        if (wr_addr_reg > 12'h0FC) 
                            s_axil_bresp <= AXIL_RESP_SLVERR;
                        else 
                            s_axil_bresp <= AXIL_RESP_OKAY;

                        wr_state <= AXIL_RESP;
                    end
                end
                
                AXIL_RESP: begin
                    if (s_axil_bready) begin
                        s_axil_bvalid <= 1'b0;
                        wr_state <= AXIL_IDLE;
                    end
                end
                
                default: wr_state <= AXIL_IDLE;
            endcase
        end
    end

    // =========================================================================
    // AXI-Lite Read State Machine
    // =========================================================================
    logic [DATA_W-1:0] rdata_mux;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_state       <= AXIL_IDLE;
            rd_addr_reg    <= '0;
            s_axil_arready <= 1'b0;
            s_axil_rvalid  <= 1'b0;
            s_axil_rresp   <= AXIL_RESP_OKAY;
        end else begin
            case (rd_state)
                AXIL_IDLE: begin
                    s_axil_arready <= 1'b1;
                    s_axil_rvalid  <= 1'b0;
                    
                    if (s_axil_arvalid && s_axil_arready) begin
                        rd_addr_reg <= s_axil_araddr;
                        s_axil_arready <= 1'b0;
                        rd_state <= AXIL_READ;
                    end
                end
                
                AXIL_READ: begin
                    s_axil_rvalid <= 1'b1;
 
                    if (rd_addr_reg > 12'h0FC) 
                        s_axil_rresp <= AXIL_RESP_SLVERR;
                    else 
                        s_axil_rresp <= AXIL_RESP_OKAY;

                    rd_state <= AXIL_RESP;
                end
                
                AXIL_RESP: begin
                    if (s_axil_rready) begin
                        s_axil_rvalid <= 1'b0;
                        rd_state <= AXIL_IDLE;
                    end
                end
                
                default: rd_state <= AXIL_IDLE;
            endcase
        end
    end

    // =========================================================================
    // Write Logic
    // =========================================================================
    logic do_write;
    assign do_write = (wr_state == AXIL_WRITE) && !s_axil_awready && !s_axil_wready;
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            reg_ctrl         <= '0;
            reg_tile_cfg     <= 32'h0008_0080;
            reg_sparsity_cfg <= 32'h0000_0001;
            reg_axis_ctrl    <= '0;
            reg_irq_enable   <= '0;
            reg_irq_status   <= '0;
            reg_pp_ctrl      <= '0;
            reg_pp_scale     <= 32'h0000_0001;
            reg_pp_shift     <= '0;
            reg_pp_sat_max   <= 32'h7FFF_FFFF;
            reg_pp_sat_min   <= 32'h8000_0000;
            reg_act_tile_cfg <= 32'h0001_0000;  // V18.2: Default act_tile_count = 1
            for (int i = 0; i < 8; i++)
                reg_pp_bias[i] <= '0;
            // V18.3: Scalable bias memory reset
            for (int i = 0; i < COLS_P; i++)
                bias_mem[i] <= '0;
            bias_wr_addr <= '0;
            use_scalable_bias <= 1'b0;
            start_pulse      <= 1'b0;
            reset_pulse      <= 1'b0;
            abort_pulse      <= 1'b0;
            clear_pulse      <= 1'b0;
        end else begin
            start_pulse <= 1'b0;
            reset_pulse <= 1'b0;
            abort_pulse <= 1'b0;
            clear_pulse <= 1'b0;
            
            reg_irq_status <= reg_irq_status | irq_status_in;
            
            if (do_write) begin
                case (wr_addr_reg)
                    CSR_CTRL: begin
                        reg_ctrl    <= wr_data_reg;
                        start_pulse <= wr_data_reg[CTRL_START_BIT];
                        reset_pulse <= wr_data_reg[CTRL_SOFT_RST_BIT];
                        abort_pulse <= wr_data_reg[CTRL_ABORT_BIT];
                        clear_pulse <= wr_data_reg[CTRL_FLUSH_BIT];
                    end
                    CSR_TILE_CFG:     reg_tile_cfg     <= wr_data_reg;
                    CSR_SPARSITY:     reg_sparsity_cfg <= wr_data_reg;
                    CSR_AXIS_CTRL:    reg_axis_ctrl    <= wr_data_reg;
                    CSR_IRQ_EN:       reg_irq_enable   <= wr_data_reg[7:0];
                    CSR_IRQ_STATUS:   reg_irq_status   <= reg_irq_status & ~wr_data_reg[7:0];
                    
                    CSR_PP_CTRL:      reg_pp_ctrl      <= wr_data_reg;
                    CSR_PP_SCALE:     reg_pp_scale     <= wr_data_reg;
                    CSR_PP_SHIFT:     reg_pp_shift     <= wr_data_reg;
                    CSR_PP_SAT_MAX:   reg_pp_sat_max   <= wr_data_reg;
                    CSR_PP_SAT_MIN:   reg_pp_sat_min   <= wr_data_reg;
                    CSR_PP_BIAS_0: begin
                        reg_pp_bias[0] <= wr_data_reg;
                        // Also write to scalable bias mem for compatibility
                        if (0 < COLS_P) bias_mem[0] <= wr_data_reg[PP_BIAS_WIDTH-1:0];
                        if (1 < COLS_P) bias_mem[1] <= wr_data_reg[PP_BIAS_WIDTH*2-1:PP_BIAS_WIDTH];
                    end
                    CSR_PP_BIAS_1: begin
                        reg_pp_bias[1] <= wr_data_reg;
                        if (2 < COLS_P) bias_mem[2] <= wr_data_reg[PP_BIAS_WIDTH-1:0];
                        if (3 < COLS_P) bias_mem[3] <= wr_data_reg[PP_BIAS_WIDTH*2-1:PP_BIAS_WIDTH];
                    end
                    CSR_PP_BIAS_2: begin
                        reg_pp_bias[2] <= wr_data_reg;
                        if (4 < COLS_P) bias_mem[4] <= wr_data_reg[PP_BIAS_WIDTH-1:0];
                        if (5 < COLS_P) bias_mem[5] <= wr_data_reg[PP_BIAS_WIDTH*2-1:PP_BIAS_WIDTH];
                    end
                    CSR_PP_BIAS_3: begin
                        reg_pp_bias[3] <= wr_data_reg;
                        if (6 < COLS_P) bias_mem[6] <= wr_data_reg[PP_BIAS_WIDTH-1:0];
                        if (7 < COLS_P) bias_mem[7] <= wr_data_reg[PP_BIAS_WIDTH*2-1:PP_BIAS_WIDTH];
                    end
                    CSR_PP_BIAS_4: begin
                        reg_pp_bias[4] <= wr_data_reg;
                        if (8 < COLS_P) bias_mem[8] <= wr_data_reg[PP_BIAS_WIDTH-1:0];
                        if (9 < COLS_P) bias_mem[9] <= wr_data_reg[PP_BIAS_WIDTH*2-1:PP_BIAS_WIDTH];
                    end
                    CSR_PP_BIAS_5: begin
                        reg_pp_bias[5] <= wr_data_reg;
                        if (10 < COLS_P) bias_mem[10] <= wr_data_reg[PP_BIAS_WIDTH-1:0];
                        if (11 < COLS_P) bias_mem[11] <= wr_data_reg[PP_BIAS_WIDTH*2-1:PP_BIAS_WIDTH];
                    end
                    CSR_PP_BIAS_6: begin
                        reg_pp_bias[6] <= wr_data_reg;
                        if (12 < COLS_P) bias_mem[12] <= wr_data_reg[PP_BIAS_WIDTH-1:0];
                        if (13 < COLS_P) bias_mem[13] <= wr_data_reg[PP_BIAS_WIDTH*2-1:PP_BIAS_WIDTH];
                    end
                    CSR_PP_BIAS_7: begin
                        reg_pp_bias[7] <= wr_data_reg;
                        if (14 < COLS_P) bias_mem[14] <= wr_data_reg[PP_BIAS_WIDTH-1:0];
                        if (15 < COLS_P) bias_mem[15] <= wr_data_reg[PP_BIAS_WIDTH*2-1:PP_BIAS_WIDTH];
                    end
                    
                    // V18.3: Scalable bias memory interface
                    CSR_PP_BIAS_ADDR: begin
                        bias_wr_addr <= wr_data_reg[7:0];
                        use_scalable_bias <= 1'b1;  // Enable scalable mode
                    end
                    CSR_PP_BIAS_DATA: begin
                        // Write single bias, auto-increment address
                        if (bias_wr_addr < COLS_P)
                            bias_mem[bias_wr_addr] <= wr_data_reg[PP_BIAS_WIDTH-1:0];
                        bias_wr_addr <= bias_wr_addr + 1;
                        use_scalable_bias <= 1'b1;
                    end
                    
                    // V18.2: Activation tile count
                    CSR_ACT_TILE_CFG: reg_act_tile_cfg <= wr_data_reg;
                    
                    default: ;
                endcase
            end
        end
    end

    // =========================================================================
    // Read Logic
    // =========================================================================
    always_comb begin
        rdata_mux = 32'hDEAD_BEEF;
        
        case (rd_addr_reg)
            CSR_CTRL:         rdata_mux = reg_ctrl;
            CSR_STATUS:       rdata_mux = {21'b0, status_state, status_done, status_busy};
            CSR_TILE_CFG:     rdata_mux = reg_tile_cfg;
            CSR_SPARSITY:     rdata_mux = reg_sparsity_cfg;
            
            CSR_IRQ_EN:       rdata_mux = {24'b0, reg_irq_enable};
            CSR_IRQ_STATUS:   rdata_mux = {24'b0, reg_irq_status};
            
            CSR_AXIS_WFIFO:   rdata_mux = {24'b0, wfifo_empty, wfifo_full, 1'b0, wfifo_level};
            CSR_AXIS_AFIFO:   rdata_mux = {24'b0, afifo_empty, afifo_full, 1'b0, afifo_level};
            CSR_AXIS_RFIFO:   rdata_mux = {24'b0, rfifo_empty, rfifo_full, 1'b0, rfifo_level};
            CSR_AXIS_CTRL:    rdata_mux = reg_axis_ctrl;
            
            CSR_PERF_CYCLES:  rdata_mux = perf_cycles;
            CSR_PERF_STALL:   rdata_mux = perf_stalls;
            CSR_PERF_MAC:     rdata_mux = perf_macs;
            CSR_PERF_ZW:      rdata_mux = perf_zero_weights;
            CSR_PERF_ZA:      rdata_mux = perf_zero_acts;
            
            CSR_PP_CTRL:      rdata_mux = reg_pp_ctrl;
            CSR_PP_SCALE:     rdata_mux = reg_pp_scale;
            CSR_PP_SHIFT:     rdata_mux = reg_pp_shift;
            CSR_PP_SAT_MAX:   rdata_mux = reg_pp_sat_max;
            CSR_PP_SAT_MIN:   rdata_mux = reg_pp_sat_min;
            CSR_PP_BIAS_0:    rdata_mux = reg_pp_bias[0];
            CSR_PP_BIAS_1:    rdata_mux = reg_pp_bias[1];
            CSR_PP_BIAS_2:    rdata_mux = reg_pp_bias[2];
            CSR_PP_BIAS_3:    rdata_mux = reg_pp_bias[3];
            CSR_PP_BIAS_4:    rdata_mux = reg_pp_bias[4];
            CSR_PP_BIAS_5:    rdata_mux = reg_pp_bias[5];
            CSR_PP_BIAS_6:    rdata_mux = reg_pp_bias[6];
            CSR_PP_BIAS_7:    rdata_mux = reg_pp_bias[7];
            
            // V18.2: Activation tile count
            CSR_ACT_TILE_CFG: rdata_mux = reg_act_tile_cfg;
            
            CSR_CAP0:         rdata_mux = {8'(PE_STAGES), 6'b0, 2'b11, 8'(COLS_P), 8'(ROWS_P)};
            CSR_CAP1:         rdata_mux = CAP1_VALUE;
            CSR_CAP2:         rdata_mux = CAP2_VALUE;
            CSR_VERSION:      rdata_mux = IP_VERSION;
            
            default:          rdata_mux = 32'hDEAD_BEEF;
        endcase
    end
    
    assign s_axil_rdata = rdata_mux;

    // =========================================================================
    // Output Assignments
    // =========================================================================
    assign ctrl_enable     = reg_ctrl[CTRL_ENABLE_BIT];
    assign ctrl_start      = start_pulse;
    assign ctrl_soft_reset = reset_pulse;
    assign ctrl_abort      = abort_pulse;
    assign ctrl_clear      = clear_pulse;
    
    assign mode_dense      = reg_sparsity_cfg[0];
    assign sparsity_cfg    = sparsity_mode_e'(reg_sparsity_cfg[2:1]);
    assign activation_fn   = activation_e'(reg_sparsity_cfg[5:3]);
    
    assign tile_count      = reg_tile_cfg[31:16];
    assign vector_count    = reg_tile_cfg[15:0];
    
    // V18.2: Activation tile count (default 1 if 0)
    assign act_tile_count  = (reg_act_tile_cfg[31:16] == 16'd0) ? 16'd1 : reg_act_tile_cfg[31:16];
    
    // Post-Processing outputs
    assign pp_op_sel   = postproc_op_e'(reg_pp_ctrl[PP_OP_MSB:PP_OP_LSB]);
    assign pp_round_en = reg_pp_ctrl[PP_ROUND_EN_BIT];
    assign pp_sat_en   = reg_pp_ctrl[PP_SAT_EN_BIT];
    assign pp_scale    = reg_pp_scale[PP_SCALE_WIDTH-1:0];
    assign pp_shift    = reg_pp_shift[PP_SHIFT_WIDTH-1:0];
    assign pp_sat_max  = reg_pp_sat_max;
    assign pp_sat_min  = reg_pp_sat_min;
    
    // V18.3: Scalable bias - use bias_mem for ALL columns
    // Legacy CSR writes also update bias_mem, so this is always correct
    generate
        for (genvar i = 0; i < COLS_P; i++) begin : gen_bias_out
            assign pp_bias[i] = bias_mem[i];
        end
    endgenerate
    
    // IRQ
    assign irq_enable = reg_irq_enable;
    assign irq_clear  = do_write && (wr_addr_reg == CSR_IRQ_STATUS) ? wr_data_reg[7:0] : '0;
    assign irq_out    = |(reg_irq_status & reg_irq_enable);

endmodule


// =============================================================================
// MODULE: compute_controller_v18
// Description: Main compute FSM with weight prefetch support (V18.3)
//              - Weight reuse for multiple activation tiles
//              - Overlapped weight loading during compute (prefetch)
// =============================================================================
module compute_controller_v18
    import accel_pkg_v18::*;
#(
    parameter int ROWS_P = ROWS,
    parameter int COLS_P = COLS
)(
    input  logic                          clk,
    input  logic                          rst_n,
    
    // Control from CSR
    input  logic                          enable,
    input  logic                          start,
    input  logic                          soft_reset,
    input  logic                          abort,
    input  logic                          mode_dense,
    input  logic [15:0]                   tile_count,
    input  logic [15:0]                   vector_count,
    input  logic [15:0]                   act_tile_count,  // V18.2: Activation tiles per weight load
    
    // Weight interface
    input  logic                          wgt_tile_ready,   // Tile available in buffer
    input  logic                          wgt_can_accept,   // Buffer can accept new tile (for prefetch)
    output logic                          wgt_tile_start,   // Start reading tile to array
    output logic                          wgt_prefetch_start, // V18.3: Start loading next tile (prefetch)
    output logic                          wgt_row_next,
    input  logic                          wgt_row_valid,
    input  logic                          wgt_last_row,
    output logic                          wgt_tile_done,
    
    // Activation interface
    output logic                          act_ready,
    input  logic                          act_valid,
    input  logic                          act_last,
    
    // Array control
    output logic                          load_en,
    output logic                          compute_en,
    output logic                          drain_en,
    output logic                          stall_phase,
    output logic [$clog2(ROWS_P)-1:0]     load_row_sel,
    output logic                          input_valid,
    
    // Result interface
    input  logic                          result_valid,
    output logic                          result_read,
    input  logic                          result_fifo_full,
    
    // Status
    output logic                          busy,
    output logic                          done,
    output compute_state_e                state_out,
    output logic                          error_flag
);

    // =========================================================================
    // Pipeline Latency Calculation
    // =========================================================================
    localparam int PIPELINE_LATENCY = 2 + (ROWS_P-1) + (ROWS_P * PE_STAGES) + 
                                       ((COLS_P-1) * PE_STAGES) + 1 + 8;

    // =========================================================================
    // State Machine
    // =========================================================================
    compute_state_e state_q, state_d;
    
    // Counters
    logic [15:0]                   tile_cnt;       // Weight tile counter
    logic [15:0]                   act_tile_cnt;   // V18.2: Activation tile counter
    logic [15:0]                   vector_cnt;
    logic [$clog2(ROWS_P)-1:0]     weight_row_cnt;
    logic                          phase_q;
    logic [7:0]                    drain_cnt;
    
    logic                          stream_active;
    assign stream_active = (state_q == S_STREAM);
    
    // V18.3: Prefetch tracking
    logic [15:0]                   prefetch_tile_cnt;  // Tiles queued for prefetch
    logic                          prefetch_pending;   // Prefetch in progress
    logic                          prefetch_issued;    // Prefetch was issued this tile
    logic                          need_more_tiles;    // More weight tiles needed
    
    assign need_more_tiles = (tile_cnt + prefetch_tile_cnt + 1 < tile_count);
    
    // Completion tracking
    logic inputs_done;
    logic pipeline_drained;
    logic backpressure;
    
    assign inputs_done      = (vector_cnt >= vector_count);
    assign pipeline_drained = inputs_done && (drain_cnt >= PIPELINE_LATENCY);
    assign backpressure     = result_fifo_full;

    // =========================================================================
    // State Register
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state_q <= S_IDLE;
        else if (soft_reset)
            state_q <= S_IDLE;
        else
            state_q <= state_d;
    end

    // =========================================================================
    // Next State Logic (V18.2: Modified S_DONE for weight reuse)
    // =========================================================================
    always_comb begin
        state_d = state_q;
        case (state_q)
            S_IDLE: begin
                if (enable && start) begin
                    if (wgt_tile_ready)
                        state_d = S_LOAD_WEIGHTS;
                    else
                        state_d = S_STREAM;
                end
            end
            
            S_LOAD_WEIGHTS: begin
                if (abort)
                    state_d = S_ERROR;
                else if (wgt_row_valid && wgt_last_row)
                    state_d = S_STREAM;
            end
            
            S_STREAM: begin
                if (abort)
                    state_d = S_ERROR;
                else if (inputs_done)
                    state_d = S_DRAIN;
            end
            
            S_DRAIN: begin
                if (abort)
                    state_d = S_ERROR;
                else if (pipeline_drained)
                    state_d = S_DONE;
            end
            
            // =====================================================================
            // V18.2: Modified S_DONE - Skip weight reload for multi-tile activation
            // =====================================================================
            S_DONE: begin
                // Check if more activation tiles to process with current weights
                if (act_tile_cnt + 1 < act_tile_count) begin
                    // More activation tiles to process - skip weight reload!
                    state_d = S_STREAM;
                end
                // Check if more weight tiles to process
                else if (tile_cnt + 1 >= tile_count) begin
                    // All done
                    state_d = S_IDLE;
                end
                else if (wgt_tile_ready) begin
                    // Load next weight tile
                    state_d = S_LOAD_WEIGHTS;
                end
                else begin
                    // No weights ready, stream anyway
                    state_d = S_STREAM;
                end
            end
            
            S_ERROR: begin
                state_d = S_RECOVERY;
            end
            
            S_RECOVERY: begin
                if (drain_cnt >= 8'd32)
                    state_d = S_IDLE;
            end
            
            default: state_d = S_IDLE;
        endcase
    end

    // =========================================================================
    // Datapath Control (V18.3: Added prefetch management)
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tile_cnt         <= '0;
            act_tile_cnt     <= '0;
            vector_cnt       <= '0;
            weight_row_cnt   <= '0;
            phase_q          <= 1'b0;
            drain_cnt        <= '0;
            prefetch_tile_cnt <= '0;
            prefetch_issued  <= 1'b0;
        end else if (soft_reset) begin
            tile_cnt         <= '0;
            act_tile_cnt     <= '0;
            vector_cnt       <= '0;
            weight_row_cnt   <= '0;
            phase_q          <= 1'b0;
            drain_cnt        <= '0;
            prefetch_tile_cnt <= '0;
            prefetch_issued  <= 1'b0;
        end else begin
            case (state_q)
                S_IDLE: begin
                    tile_cnt         <= '0;
                    act_tile_cnt     <= '0;
                    vector_cnt       <= '0;
                    weight_row_cnt   <= '0;
                    phase_q          <= 1'b0;
                    drain_cnt        <= '0;
                    prefetch_tile_cnt <= '0;
                    prefetch_issued  <= 1'b0;
                end
                
                S_LOAD_WEIGHTS: begin
                    if (wgt_row_valid)
                        weight_row_cnt <= weight_row_cnt + 1;
                end
                
                S_STREAM: begin
                    if (!backpressure && act_valid) begin
                        phase_q <= ~phase_q;
                        if (!inputs_done) begin
                            if (mode_dense) begin
                                if (phase_q)
                                    vector_cnt <= vector_cnt + 1;
                            end else begin
                                vector_cnt <= vector_cnt + 1;
                            end
                        end
                    end
                    
                    // V18.3: Issue prefetch early in S_STREAM if not already done
                    if (!prefetch_issued && need_more_tiles && wgt_can_accept) begin
                        prefetch_tile_cnt <= prefetch_tile_cnt + 1;
                        prefetch_issued <= 1'b1;
                    end
                end
                
                S_DRAIN: begin
                    if (drain_cnt < PIPELINE_LATENCY + 8)
                        drain_cnt <= drain_cnt + 1;
                    
                    // V18.3: Can also issue prefetch during drain
                    if (!prefetch_issued && need_more_tiles && wgt_can_accept) begin
                        prefetch_tile_cnt <= prefetch_tile_cnt + 1;
                        prefetch_issued <= 1'b1;
                    end
                end
                
                // =====================================================================
                // V18.3: Updated S_DONE - Manage prefetch and tile counters
                // =====================================================================
                S_DONE: begin
                    if (act_tile_cnt + 1 < act_tile_count) begin
                        // More activation tiles with same weights
                        act_tile_cnt   <= act_tile_cnt + 1;
                        vector_cnt     <= '0;
                        drain_cnt      <= '0;
                        prefetch_issued <= 1'b0;  // Allow new prefetch
                        // Keep weight_row_cnt - weights stay loaded!
                    end else begin
                        // Move to next weight tile
                        act_tile_cnt   <= '0;
                        tile_cnt       <= tile_cnt + 1;
                        vector_cnt     <= '0;
                        weight_row_cnt <= '0;
                        drain_cnt      <= '0;
                        prefetch_issued <= 1'b0;  // Allow new prefetch
                        // Decrement prefetch count since we're consuming one
                        if (prefetch_tile_cnt > 0)
                            prefetch_tile_cnt <= prefetch_tile_cnt - 1;
                    end
                end
                
                default: ;
            endcase
        end
    end

    // =========================================================================
    // Sticky Done Flag (V18.2: Account for all activation tiles)
    // =========================================================================
    logic done_sticky;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            done_sticky <= 1'b0;
        else if (start)
            done_sticky <= 1'b0;
        else if (state_q == S_DONE && 
                 (tile_cnt >= tile_count - 1) && 
                 (act_tile_cnt + 1 >= act_tile_count))
            done_sticky <= 1'b1;
    end

    // =========================================================================
    // Output Assignments
    // =========================================================================
    assign busy        = (state_q != S_IDLE);
    assign done        = done_sticky;
    assign state_out   = state_q;
    assign error_flag  = (state_q == S_ERROR);
    
    // V18.2: Only start weight tile on first activation tile or new weight tile
    assign wgt_tile_start = ((state_q == S_IDLE) || 
                             (state_q == S_DONE && act_tile_cnt + 1 >= act_tile_count)) && 
                            start && wgt_tile_ready;
    assign wgt_row_next   = (state_q == S_LOAD_WEIGHTS);
    assign wgt_tile_done  = (state_q == S_LOAD_WEIGHTS) && wgt_row_valid && wgt_last_row;
    
    // V18.3: Prefetch next weight tile during compute/drain
    // Issue pulse when transitioning to prefetch
    logic prefetch_trigger;
    assign prefetch_trigger = !prefetch_issued && need_more_tiles && wgt_can_accept &&
                              ((state_q == S_STREAM) || (state_q == S_DRAIN));
    assign wgt_prefetch_start = prefetch_trigger;
    
    assign load_en      = (state_q == S_LOAD_WEIGHTS) && wgt_row_valid;
    assign load_row_sel = weight_row_cnt;
    
    assign compute_en   = ((state_q == S_STREAM) || (state_q == S_DRAIN)) && !backpressure;
    assign drain_en     = (state_q == S_DRAIN);
    assign stall_phase  = phase_q;
    assign input_valid  = (state_q == S_STREAM) && !inputs_done && !backpressure && act_valid;
    
    assign act_ready    = (state_q == S_STREAM) && !inputs_done && !backpressure;
    
    // FIX: Enable concurrent result drain during STREAM to prevent OFIFO deadlock
    // Results now drain WHILE streaming activations (true pipelined operation)
    assign result_read  = ((state_q == S_STREAM) || (state_q == S_DRAIN)) && 
                          result_valid && !result_fifo_full;

endmodule


// =============================================================================
// MODULE: irq_controller_v18
// =============================================================================
module irq_controller_v18 #(
    parameter int NUM_SOURCES = 8
)(
    input  logic                     clk,
    input  logic                     rst_n,
    
    input  logic [NUM_SOURCES-1:0]   irq_sources,
    input  logic                     global_enable,
    input  logic [NUM_SOURCES-1:0]   irq_mask,
    
    output logic [NUM_SOURCES-1:0]   irq_status,
    input  logic [NUM_SOURCES-1:0]   irq_clear,
    
    output logic                     irq_out
);

    logic [NUM_SOURCES-1:0] irq_sources_d;
    logic [NUM_SOURCES-1:0] irq_rising;
    logic [NUM_SOURCES-1:0] irq_pending;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            irq_sources_d <= '0;
        else
            irq_sources_d <= irq_sources;
    end

    assign irq_rising = irq_sources & ~irq_sources_d;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            irq_pending <= '0;
        else
            irq_pending <= (irq_pending | irq_rising) & ~irq_clear;
    end

    assign irq_status = irq_pending;
    assign irq_out    = |(irq_pending & irq_mask) && global_enable;

endmodule


// =============================================================================
// MODULE: perf_counters_v18
// =============================================================================
module perf_counters_v18
    import accel_pkg_v18::*;
#(
    parameter int ROWS_P = ROWS,
    parameter int COLS_P = COLS
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          clear,
    input  logic                          enable,
    
    input  logic                          compute_active,
    input  logic                          stall_condition,
    
    input  logic [ROWS_P*COLS_P-1:0]      pe_zero_weight_map,
    input  logic [ROWS_P*COLS_P-1:0]      pe_zero_act_map,
    input  logic [ROWS_P*COLS_P-1:0]      pe_mac_active_map,
    
    output logic [31:0]                   cnt_cycles,
    output logic [31:0]                   cnt_stalls,
    output logic [31:0]                   cnt_macs,
    output logic [31:0]                   cnt_zero_weights,
    output logic [31:0]                   cnt_zero_acts
);

    function automatic int popcount(input logic [ROWS_P*COLS_P-1:0] bits);
        int count = 0;
        for (int i = 0; i < ROWS_P*COLS_P; i++)
            count += bits[i];
        return count;
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt_cycles       <= '0;
            cnt_stalls       <= '0;
            cnt_macs         <= '0;
            cnt_zero_weights <= '0;
            cnt_zero_acts    <= '0;
        end else if (clear) begin
            cnt_cycles       <= '0;
            cnt_stalls       <= '0;
            cnt_macs         <= '0;
            cnt_zero_weights <= '0;
            cnt_zero_acts    <= '0;
        end else if (enable) begin
            if (compute_active) begin
                cnt_cycles <= cnt_cycles + 1;
                if (stall_condition)
                    cnt_stalls <= cnt_stalls + 1;
                cnt_macs         <= cnt_macs + popcount(pe_mac_active_map);
                cnt_zero_weights <= cnt_zero_weights + popcount(pe_zero_weight_map);
                cnt_zero_acts    <= cnt_zero_acts + popcount(pe_zero_act_map);
            end
        end
    end

endmodule


// =============================================================================
// MODULE: control_top_v18
// Description: Control subsystem top-level (V18.3 with weight prefetch)
// =============================================================================
module control_top_v18
    import accel_pkg_v18::*;
#(
    parameter int ROWS_P = ROWS,
    parameter int COLS_P = COLS
)(
    input  logic                          clk,
    input  logic                          rst_n,
    
    // AXI4-Lite Interface
    input  logic [AXIL_ADDR_WIDTH-1:0]    s_axil_awaddr,
    input  logic [2:0]                    s_axil_awprot,
    input  logic                          s_axil_awvalid,
    output logic                          s_axil_awready,
    
    input  logic [AXIL_DATA_WIDTH-1:0]    s_axil_wdata,
    input  logic [AXIL_STRB_WIDTH-1:0]    s_axil_wstrb,
    input  logic                          s_axil_wvalid,
    output logic                          s_axil_wready,
    
    output logic [1:0]                    s_axil_bresp,
    output logic                          s_axil_bvalid,
    input  logic                          s_axil_bready,
    
    input  logic [AXIL_ADDR_WIDTH-1:0]    s_axil_araddr,
    input  logic [2:0]                    s_axil_arprot,
    input  logic                          s_axil_arvalid,
    output logic                          s_axil_arready,
    
    output logic [AXIL_DATA_WIDTH-1:0]    s_axil_rdata,
    output logic [1:0]                    s_axil_rresp,
    output logic                          s_axil_rvalid,
    input  logic                          s_axil_rready,
    
    // Weight interface
    input  logic                          wgt_tile_ready,
    input  logic                          wgt_can_accept,   // V18.3: Buffer can accept prefetch
    output logic                          wgt_tile_start,
    output logic                          wgt_prefetch_start, // V18.3: Prefetch trigger
    output logic                          wgt_row_next,
    input  logic                          wgt_row_valid,
    input  logic                          wgt_last_row,
    output logic                          wgt_tile_done,
    
    // Activation interface
    output logic                          act_ready,
    input  logic                          act_valid,
    input  logic                          act_last,
    
    // Array control
    output logic                          load_en,
    output logic                          compute_en,
    output logic                          drain_en,
    output logic                          stall_phase,
    output logic [$clog2(ROWS_P)-1:0]     load_row_sel,
    output logic                          input_valid,
    output logic                          mode_dense,
    output sparsity_mode_e                sparsity_cfg,
    output activation_e                   activation_fn,
    
    // Post-Processing Configuration
    output postproc_op_e                     pp_op_sel,
    output logic signed [PP_BIAS_WIDTH-1:0]  pp_bias [COLS_P],
    output logic signed [PP_SCALE_WIDTH-1:0] pp_scale,
    output logic [PP_SHIFT_WIDTH-1:0]        pp_shift,
    output logic                             pp_round_en,
    output logic                             pp_sat_en,
    output logic signed [ACC_WIDTH-1:0]      pp_sat_max,
    output logic signed [ACC_WIDTH-1:0]      pp_sat_min,
    
    // Result interface
    input  logic                          result_valid,
    output logic                          result_read,
    input  logic                          result_fifo_full,
    
    output logic [15:0]                   drain_vector_count,
    
    // FIFO status
    input  logic [4:0]                    wfifo_level,
    input  logic                          wfifo_full,
    input  logic                          wfifo_empty,
    input  logic [4:0]                    afifo_level,
    input  logic                          afifo_full,
    input  logic                          afifo_empty,
    input  logic [4:0]                    rfifo_level,
    input  logic                          rfifo_full,
    input  logic                          rfifo_empty,
    
    // Performance monitoring inputs
    input  logic [ROWS_P*COLS_P-1:0]      pe_zero_weight_map,
    input  logic [ROWS_P*COLS_P-1:0]      pe_zero_act_map,
    input  logic [ROWS_P*COLS_P-1:0]      pe_mac_active_map,
    
    // IRQ
    output logic                          irq_out,
    output logic                          ctrl_clear_out
);

    // Internal signals
    logic        ctrl_enable, ctrl_start, ctrl_soft_reset, ctrl_abort, ctrl_clear;
    logic [15:0] tile_count, vector_count;
    logic [15:0] act_tile_count;  // V18.2: New signal
    logic        busy, done, error_flag;
    compute_state_e state;
    
    logic [7:0]  irq_enable, irq_clear_sig;
    logic [7:0]  irq_sources;
    logic [7:0]  irq_status;
    
    logic [31:0] perf_cycles, perf_stalls, perf_macs, perf_zw, perf_za;

    // =========================================================================
    // CSR Block (V18.2: Added act_tile_count output)
    // =========================================================================
    accel_csr_axil_v18 #(
        .ROWS_P(ROWS_P),
        .COLS_P(COLS_P)
    ) u_csr (
        .clk             (clk),
        .rst_n           (rst_n),
        
        // AXI-Lite
        .s_axil_awaddr   (s_axil_awaddr),
        .s_axil_awprot   (s_axil_awprot),
        .s_axil_awvalid  (s_axil_awvalid),
        .s_axil_awready  (s_axil_awready),
        .s_axil_wdata    (s_axil_wdata),
        .s_axil_wstrb    (s_axil_wstrb),
        .s_axil_wvalid   (s_axil_wvalid),
        .s_axil_wready   (s_axil_wready),
        .s_axil_bresp    (s_axil_bresp),
        .s_axil_bvalid   (s_axil_bvalid),
        .s_axil_bready   (s_axil_bready),
        .s_axil_araddr   (s_axil_araddr),
        .s_axil_arprot   (s_axil_arprot),
        .s_axil_arvalid  (s_axil_arvalid),
        .s_axil_arready  (s_axil_arready),
        .s_axil_rdata    (s_axil_rdata),
        .s_axil_rresp    (s_axil_rresp),
        .s_axil_rvalid   (s_axil_rvalid),
        .s_axil_rready   (s_axil_rready),
        
        // Control outputs
        .ctrl_enable     (ctrl_enable),
        .ctrl_start      (ctrl_start),
        .ctrl_soft_reset (ctrl_soft_reset),
        .ctrl_abort      (ctrl_abort),
        .ctrl_clear      (ctrl_clear),
        .mode_dense      (mode_dense),
        .sparsity_cfg    (sparsity_cfg),
        .activation_fn   (activation_fn),
        .tile_count      (tile_count),
        .vector_count    (vector_count),
        .act_tile_count  (act_tile_count),  // V18.2: New
        
        // Post-processing config
        .pp_op_sel       (pp_op_sel),
        .pp_bias         (pp_bias),
        .pp_scale        (pp_scale),
        .pp_shift        (pp_shift),
        .pp_round_en     (pp_round_en),
        .pp_sat_en       (pp_sat_en),
        .pp_sat_max      (pp_sat_max),
        .pp_sat_min      (pp_sat_min),
        
        // Status inputs
        .status_busy     (busy),
        .status_done     (done),
        .status_state    (state),
        .wfifo_level     (wfifo_level),
        .wfifo_full      (wfifo_full),
        .wfifo_empty     (wfifo_empty),
        .afifo_level     (afifo_level),
        .afifo_full      (afifo_full),
        .afifo_empty     (afifo_empty),
        .rfifo_level     (rfifo_level),
        .rfifo_full      (rfifo_full),
        .rfifo_empty     (rfifo_empty),
        .perf_cycles     (perf_cycles),
        .perf_stalls     (perf_stalls),
        .perf_macs       (perf_macs),
        .perf_zero_weights(perf_zw),
        .perf_zero_acts  (perf_za),
        .irq_enable      (irq_enable),
        .irq_status_in   (irq_status),
        .irq_clear       (irq_clear_sig),
        .irq_out         (irq_out)
    );

    // =========================================================================
    // Compute Controller (V18.3: Added prefetch support)
    // =========================================================================
    compute_controller_v18 #(
        .ROWS_P(ROWS_P),
        .COLS_P(COLS_P)
    ) u_compute (
        .clk             (clk),
        .rst_n           (rst_n),
        .enable          (ctrl_enable),
        .start           (ctrl_start),
        .soft_reset      (ctrl_soft_reset),
        .abort           (ctrl_abort),
        .mode_dense      (mode_dense),
        .tile_count      (tile_count),
        .vector_count    (vector_count),
        .act_tile_count  (act_tile_count),
        .wgt_tile_ready  (wgt_tile_ready),
        .wgt_can_accept  (wgt_can_accept),     // V18.3: New
        .wgt_tile_start  (wgt_tile_start),
        .wgt_prefetch_start(wgt_prefetch_start), // V18.3: New
        .wgt_row_next    (wgt_row_next),
        .wgt_row_valid   (wgt_row_valid),
        .wgt_last_row    (wgt_last_row),
        .wgt_tile_done   (wgt_tile_done),
        .act_ready       (act_ready),
        .act_valid       (act_valid),
        .act_last        (act_last),
        .load_en         (load_en),
        .compute_en      (compute_en),
        .drain_en        (drain_en),
        .stall_phase     (stall_phase),
        .load_row_sel    (load_row_sel),
        .input_valid     (input_valid),
        .result_valid    (result_valid),
        .result_read     (result_read),
        .result_fifo_full(result_fifo_full),
        .busy            (busy),
        .done            (done),
        .state_out       (state),
        .error_flag      (error_flag)
    );

    assign drain_vector_count = vector_count;

    // =========================================================================
    // IRQ Sources
    // =========================================================================
    assign irq_sources = {
        1'b0,
        error_flag,
        rfifo_full,
        afifo_empty,
        wfifo_empty,
        1'b0,
        1'b0,
        done
    };

    irq_controller_v18 #(
        .NUM_SOURCES(8)
    ) u_irq (
        .clk           (clk),
        .rst_n         (rst_n),
        .irq_sources   (irq_sources),
        .global_enable (ctrl_enable),
        .irq_mask      (irq_enable),
        .irq_status    (irq_status),
        .irq_clear     (irq_clear_sig),
        .irq_out       ()
    );

    // =========================================================================
    // Performance Counters
    // =========================================================================
    perf_counters_v18 #(
        .ROWS_P(ROWS_P),
        .COLS_P(COLS_P)
    ) u_perf (
        .clk              (clk),
        .rst_n            (rst_n),
        .clear            (ctrl_clear),
        .enable           (ctrl_enable),
        .compute_active   (compute_en),
        .stall_condition  (result_fifo_full && compute_en),
        .pe_zero_weight_map(pe_zero_weight_map),
        .pe_zero_act_map  (pe_zero_act_map),
        .pe_mac_active_map(pe_mac_active_map),
        .cnt_cycles       (perf_cycles),
        .cnt_stalls       (perf_stalls),
        .cnt_macs         (perf_macs),
        .cnt_zero_weights (perf_zw),
        .cnt_zero_acts    (perf_za)
    );
  
    assign ctrl_clear_out = ctrl_clear;

endmodule