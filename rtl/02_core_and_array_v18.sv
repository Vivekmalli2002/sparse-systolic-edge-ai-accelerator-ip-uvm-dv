// =============================================================================
// File: 02_core_and_array_v18.sv
// Description: V18 Processing Element and Systolic Array
//              Merged V16 compute core with V18 package definitions
//              Features: 2:4 sparsity, clock gating, parity, saturation
// Version: 18.0
// =============================================================================

`timescale 1ns/1ps

// =============================================================================
// MODULE: pe_v18
// Description: Processing Element with sparse MAC, clock gating, monitoring
// Features from V16: 2:4 structured sparsity, per-PE clock gating, parity check
// =============================================================================
module pe_v18
    import accel_pkg_v18::*;
#(
    parameter int W_W       = W_WIDTH,
    parameter int A_W       = A_WIDTH,
    parameter int ACC_W     = ACC_WIDTH,
    parameter int IDX_W     = IDX_WIDTH,
    parameter int WGT_PKT_W = WGT_PKT_WIDTH,
    parameter int ACT_PKT_W = ACT_PKT_WIDTH,
    parameter bit ENABLE_CLOCK_GATING = 1,
    parameter bit ENABLE_PARITY       = 1
)(
    input  logic                      clk,
    input  logic                      rst_n,
    input  logic                      scan_enable,
    
    // Control
    input  logic                      load_en,        // Load weights
    input  logic                      compute_en,     // Enable MAC
    input  logic                      stall_phase,    // Dense mode phase select
    input  logic                      mode_dense,     // 1=dense, 0=sparse
    input  sparsity_mode_e            sparsity_cfg,   // Sparsity pattern
    
    // Weight Input (with parity)
    input  logic [WGT_PKT_W-1:0]      wgt_packet_in,  // 2 weights + 2 indices
    input  logic                      wgt_parity_in,
    input  logic                      parity_err_in,
    output logic                      parity_err_out,
    
    // Activation Dataflow (horizontal)
    input  logic [ACT_PKT_W-1:0]      act_packet_in,  // 4 activations
    output logic [ACT_PKT_W-1:0]      act_packet_out,
    
    // Partial Sum Dataflow (vertical)
    input  logic signed [ACC_W-1:0]   psum_in,
    input  logic                      psum_valid_in,
    output logic signed [ACC_W-1:0]   psum_out,
    output logic                      psum_valid_out,
    
    // Status/Monitoring
    output logic                      zero_weight_detected,
    output logic                      zero_act_detected,
    output logic                      overflow_detected,
    output pe_power_state_e           power_state,
    output logic                      mac_active
);

    // =========================================================================
    // Constants
    // =========================================================================
    localparam logic signed [ACC_W-1:0] SAT_MAX = (1 << (ACC_W-1)) - 1;
    localparam logic signed [ACC_W-1:0] SAT_MIN = -(1 << (ACC_W-1));

    // =========================================================================
    // Weight Registers
    // =========================================================================
    logic signed [W_W-1:0]   w0_reg, w1_reg;
    logic [IDX_W-1:0]        idx0_reg, idx1_reg;
    logic                    local_parity_err;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w0_reg           <= '0;
            w1_reg           <= '0;
            idx0_reg         <= '0;
            idx1_reg         <= '0;
            local_parity_err <= 1'b0;
        end else if (load_en) begin
            // Weight packet format: {idx1, idx0, w1, w0}
            {idx1_reg, idx0_reg, w1_reg, w0_reg} <= wgt_packet_in;
            if (ENABLE_PARITY)
                local_parity_err <= (^wgt_packet_in) ^ wgt_parity_in;
            else
                local_parity_err <= 1'b0;
        end
    end

    assign parity_err_out = ENABLE_PARITY ? (parity_err_in | local_parity_err) : parity_err_in;
    assign zero_weight_detected = (w0_reg == '0) && (w1_reg == '0);

    // =========================================================================
    // Activation Selection (Sparse Index Mux)
    // =========================================================================
    logic signed [A_W-1:0] a0, a1, a2, a3;
    logic signed [A_W-1:0] sel_a0, sel_a1;

    assign {a3, a2, a1, a0} = act_packet_in;

    always_comb begin
        sel_a0 = '0;
        sel_a1 = '0;
        if (compute_en) begin
            if (mode_dense) begin
                // Dense mode: process 2 activations per phase
                if (!stall_phase) begin
                    sel_a0 = a0;
                    sel_a1 = a1;
                end else begin
                    sel_a0 = a2;
                    sel_a1 = a3;
                end
            end else begin
                // Sparse mode: index selects activation
                case (idx0_reg)
                    2'd0: sel_a0 = a0;
                    2'd1: sel_a0 = a1;
                    2'd2: sel_a0 = a2;
                    2'd3: sel_a0 = a3;
                endcase
                
                // Second weight only for 2:4 and 4:8 (not 1:4)
                if (sparsity_cfg != SPARSITY_1_4) begin
                    case (idx1_reg)
                        2'd0: sel_a1 = a0;
                        2'd1: sel_a1 = a1;
                        2'd2: sel_a1 = a2;
                        2'd3: sel_a1 = a3;
                    endcase
                end
            end
        end
    end

    assign zero_act_detected = (sel_a0 == '0) && (sel_a1 == '0) && compute_en;

    // =========================================================================
    // Operand Isolation (Power Optimization)
    // =========================================================================
    logic isolate_operands;
    assign isolate_operands = zero_weight_detected | zero_act_detected;

    always_comb begin
        if (!compute_en && !load_en)
            power_state = PE_CLOCK_GATE;
        else if (isolate_operands)
            power_state = PE_IDLE;
        else if (compute_en)
            power_state = PE_ACTIVE;
        else
            power_state = PE_IDLE;
    end

    logic signed [W_W-1:0] iso_w0, iso_w1;
    logic signed [A_W-1:0] iso_a0, iso_a1;

    assign iso_w0 = isolate_operands ? '0 : w0_reg;
    assign iso_w1 = isolate_operands ? '0 : w1_reg;
    assign iso_a0 = isolate_operands ? '0 : sel_a0;
    assign iso_a1 = isolate_operands ? '0 : sel_a1;

    assign mac_active = compute_en && !isolate_operands;

    // =========================================================================
    // Clock Gating Cell
    // =========================================================================
    logic gated_clk;
    logic datapath_active;

    assign datapath_active = load_en | compute_en;

    generate
        if (ENABLE_CLOCK_GATING) begin : gen_icg
            icg_cell u_icg (
                .clk        (clk),
                .enable     (datapath_active),
                .scan_enable(scan_enable),
                .gated_clk  (gated_clk)
            );
        end else begin : gen_no_icg
            assign gated_clk = clk;
        end
    endgenerate

    // =========================================================================
    // Pipeline Stage 1: Multiply
    // =========================================================================
    logic signed [W_W+A_W:0]    product_s1;
    logic signed [ACC_W-1:0]    psum_s1;
    logic                       valid_s1;
    logic                       stall_phase_s1;
    logic                       mode_dense_s1;
    logic [ACT_PKT_W-1:0]       act_reg_s1;

    always_ff @(posedge gated_clk or negedge rst_n) begin
        if (!rst_n) begin
            product_s1     <= '0;
            psum_s1        <= '0;
            valid_s1       <= 1'b0;
            stall_phase_s1 <= 1'b0;
            mode_dense_s1  <= 1'b0;
            act_reg_s1     <= '0;
        end else if (compute_en) begin
            // Dual MAC: w0*a0 + w1*a1
            product_s1     <= (iso_w0 * iso_a0) + (iso_w1 * iso_a1);
            psum_s1        <= psum_in;
            valid_s1       <= psum_valid_in;
            stall_phase_s1 <= stall_phase;
            mode_dense_s1  <= mode_dense;
            act_reg_s1     <= act_packet_in;
        end else begin
            valid_s1 <= 1'b0;
        end
    end

    // =========================================================================
    // Pipeline Stage 2: Accumulate with Saturation
    // =========================================================================
    logic signed [ACC_W-1:0]    acc_reg;
    logic signed [ACC_W-1:0]    dense_partial;
    logic signed [ACC_W:0]      acc_extended;
    logic                       valid_s2;
    logic [ACT_PKT_W-1:0]       act_reg_s2;
    logic                       overflow_s2;
    // FIX7: Track phase and mode in S2 for psum_out gating
    logic                       stall_phase_s2;
    logic                       mode_dense_s2;

    always_ff @(posedge gated_clk or negedge rst_n) begin
        if (!rst_n) begin
            acc_reg        <= '0;
            dense_partial  <= '0;
            valid_s2       <= 1'b0;
            act_reg_s2     <= '0;
            overflow_s2    <= 1'b0;
            stall_phase_s2 <= 1'b0;
            mode_dense_s2  <= 1'b0;
        end else if (compute_en) begin
            act_reg_s2     <= act_reg_s1;
            overflow_s2    <= 1'b0;
            stall_phase_s2 <= stall_phase_s1;
            mode_dense_s2  <= mode_dense_s1;

            if (valid_s1) begin
                if (mode_dense_s1) begin
                    // Dense mode: accumulate over two phases
                    if (!stall_phase_s1) begin
                        dense_partial <= signed'(product_s1);
                    end else begin
                        acc_extended = psum_s1 + dense_partial + signed'(product_s1);
                        // Saturation check
                        if (acc_extended > signed'(SAT_MAX)) begin
                            acc_reg     <= SAT_MAX;
                            overflow_s2 <= 1'b1;
                        end else if (acc_extended < signed'(SAT_MIN)) begin
                            acc_reg     <= SAT_MIN;
                            overflow_s2 <= 1'b1;
                        end else begin
                            acc_reg <= acc_extended[ACC_W-1:0];
                        end
                    end
                end else begin
                    // Sparse mode: single accumulate
                    acc_extended = psum_s1 + signed'(product_s1);
                    if (acc_extended > signed'(SAT_MAX)) begin
                        acc_reg     <= SAT_MAX;
                        overflow_s2 <= 1'b1;
                    end else if (acc_extended < signed'(SAT_MIN)) begin
                        acc_reg     <= SAT_MIN;
                        overflow_s2 <= 1'b1;
                    end else begin
                        acc_reg <= acc_extended[ACC_W-1:0];
                    end
                end
            end

            valid_s2 <= valid_s1;
        end else begin
            valid_s2 <= 1'b0;
        end
    end

    // FIX7: In dense mode Phase 0, output 0 instead of stale acc_reg
    // This prevents previous vector's result from corrupting current vector's psum chain
    // Phase 0: store in dense_partial, pass 0 to downstream
    // Phase 1: output actual accumulated result
    assign psum_out          = (mode_dense_s2 && !stall_phase_s2) ? '0 : acc_reg;
    assign psum_valid_out    = valid_s2;
    assign act_packet_out    = act_reg_s2;
    assign overflow_detected = overflow_s2;

endmodule


// =============================================================================
// MODULE: icg_cell
// Description: Integrated Clock Gating cell with DFT bypass
// =============================================================================
module icg_cell (
    input  logic clk,
    input  logic enable,
    input  logic scan_enable,
    output logic gated_clk
);

    logic enable_latch;

    // Latch enable on negative edge (glitch-free)
    always_latch begin
        if (!clk)
            enable_latch <= enable | scan_enable;
    end

    assign gated_clk = clk & enable_latch;

endmodule


// =============================================================================
// MODULE: skew_buffer_v18
// Description: Row-wise skew for activation wavefront alignment
//              Row 0: 0 delay
//              Row r: r * PE_STAGES delay (accounts for PE pipeline depth)
// 
// FIX: The original implementation used r-cycle delay per row, but the PE
//      has PE_STAGES (2) pipeline stages. When Row0's psum propagates to Row1,
//      it takes PE_STAGES cycles. So Row1's activation must arrive PE_STAGES
//      cycles after Row0's activation. Total delay for Row r = r * PE_STAGES.
// =============================================================================
module skew_buffer_v18
    import accel_pkg_v18::*;
#(
    parameter int ROWS_P    = ROWS,
    parameter int ACT_PKT_W = ACT_PKT_WIDTH,
    parameter int PE_PIPE   = PE_STAGES  // Pipeline stages in PE (default 2)
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          enable,
    input  logic                          clear,
    input  logic [ACT_PKT_W-1:0]          act_in,
    output logic [ACT_PKT_W-1:0]          act_out [ROWS_P]
);

    generate
        for (genvar r = 0; r < ROWS_P; r++) begin : gen_row_delay
            // FIX: Multiply row index by PE pipeline stages
            localparam int DELAY = r * PE_PIPE;
            
            if (DELAY == 0) begin : gen_no_delay
                // Row 0: direct pass-through
                assign act_out[r] = act_in;
            end else begin : gen_delay
                // Row r: r * PE_STAGES cycle delay
                logic [ACT_PKT_W-1:0] delay_chain [DELAY];
                
                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        for (int i = 0; i < DELAY; i++) 
                            delay_chain[i] <= '0;
                    end else if (clear) begin
                        for (int i = 0; i < DELAY; i++) 
                            delay_chain[i] <= '0;
                    end else if (enable) begin
                        delay_chain[0] <= act_in;
                        for (int i = 1; i < DELAY; i++) 
                            delay_chain[i] <= delay_chain[i-1];
                    end
                end
                
                assign act_out[r] = delay_chain[DELAY-1];
            end
        end
    endgenerate

endmodule



// =============================================================================
// MODULE: deskew_buffer_v18
// Description: Column-wise deskew for aligned output collection
//              Col 0: max delay, Col N-1: 0 delay
// =============================================================================
module deskew_buffer_v18
    import accel_pkg_v18::*;
#(
    parameter int COLS_P    = COLS,
    parameter int ACC_W     = ACC_WIDTH,
    parameter int PE_PIPE   = PE_STAGES
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          enable,
    input  logic                          clear,
    input  logic signed [ACC_W-1:0]       psum_in     [COLS_P],
    input  logic [COLS_P-1:0]             valid_in,
    output logic signed [ACC_W-1:0]       psum_out    [COLS_P],
    output logic [COLS_P-1:0]             valid_out
);

    generate
        for (genvar c = 0; c < COLS_P; c++) begin : gen_col_delay
            // Column c delay: (COLS_P - 1 - c) * PE_PIPE cycles
            localparam int DELAY = (COLS_P - 1 - c) * PE_PIPE;
            
            if (DELAY == 0) begin : gen_no_delay
                // Last column: direct pass-through
                assign psum_out[c]  = psum_in[c];
                assign valid_out[c] = valid_in[c];
            end else begin : gen_delay
                logic signed [ACC_W-1:0] psum_shift [DELAY];
                logic                    valid_shift [DELAY];
                
                always_ff @(posedge clk or negedge rst_n) begin
                    if (!rst_n) begin
                        for (int i = 0; i < DELAY; i++) begin
                            psum_shift[i]  <= '0;
                            valid_shift[i] <= 1'b0;
                        end
                    end else if (clear) begin
                        for (int i = 0; i < DELAY; i++) begin
                            psum_shift[i]  <= '0;
                            valid_shift[i] <= 1'b0;
                        end
                    end else begin
                        // Always shift when enabled OR when valid data in pipeline
                        if (enable || valid_in[c] || valid_shift[0]) begin
                            psum_shift[0]  <= psum_in[c];
                            valid_shift[0] <= valid_in[c];
                            for (int i = 1; i < DELAY; i++) begin
                                psum_shift[i]  <= psum_shift[i-1];
                                valid_shift[i] <= valid_shift[i-1];
                            end
                        end
                    end
                end
                
                assign psum_out[c]  = psum_shift[DELAY-1];
                assign valid_out[c] = valid_shift[DELAY-1];
            end
        end
    endgenerate

endmodule


// =============================================================================
// MODULE: systolic_array_v18
// Description: 8x8 Systolic Array with integrated skew/deskew
// Features: Weight-stationary dataflow, sparse/dense modes, monitoring
// =============================================================================
module systolic_array_v18
    import accel_pkg_v18::*;
#(
    parameter int ROWS_P      = ROWS,
    parameter int COLS_P      = COLS,
    parameter int W_W         = W_WIDTH,
    parameter int A_W         = A_WIDTH,
    parameter int ACC_W       = ACC_WIDTH,
    parameter int IDX_W       = IDX_WIDTH,
    parameter int WGT_PKT_W   = WGT_PKT_WIDTH,
    parameter int ACT_PKT_W   = ACT_PKT_WIDTH,
    parameter bit ENABLE_ICG  = 1,
    parameter bit ENABLE_PAR  = 1
)(
    input  logic                              clk,
    input  logic                              rst_n,
    input  logic                              scan_enable,
    
    // Control
    input  logic                              mode_dense,
    input  sparsity_mode_e                    sparsity_cfg,
    input  logic                              load_en,
    input  logic                              compute_en,
    input  logic                              stall_phase,
    input  logic [$clog2(ROWS_P)-1:0]         load_row_sel,
    input  logic                              input_valid,
    
    // Weight Input (per column)
    input  logic [WGT_PKT_W-1:0]              wgt_in      [COLS_P],
    input  logic [COLS_P-1:0]                 wgt_parity_in,
    
    // Activation Input (per row, after skew)
    input  logic [ACT_PKT_W-1:0]              act_in      [ROWS_P],
    
    // Outputs (per column, before deskew)
    output logic signed [ACC_W-1:0]           psum_out    [COLS_P],
    output logic                              result_valid,
    output logic [COLS_P-1:0]                 col_valid,
    
    // Error Flags
    output logic                              parity_error,
    output logic                              overflow_error,
    
    // Monitoring Maps
    output logic [ROWS_P*COLS_P-1:0]          pe_zero_weight_map,
    output logic [ROWS_P*COLS_P-1:0]          pe_zero_act_map,
    output logic [ROWS_P*COLS_P-1:0]          pe_overflow_map,
    output logic [ROWS_P*COLS_P-1:0]          pe_mac_active_map,
    output pe_power_state_e                   pe_power_states [ROWS_P][COLS_P],
    output logic [$clog2(ROWS_P*COLS_P+1)-1:0] active_pe_count
);

    // =========================================================================
    // Inter-PE Wires
    // =========================================================================
    logic [ACT_PKT_W-1:0]       act_h       [ROWS_P][COLS_P+1];  // Horizontal activation
    logic signed [ACC_W-1:0]    psum_v      [ROWS_P+1][COLS_P];  // Vertical psum
    logic                       valid_v     [ROWS_P+1][COLS_P];  // Vertical valid
    logic                       parity_v    [ROWS_P+1][COLS_P];  // Vertical parity
    logic                       pe_load_en  [ROWS_P][COLS_P];
    logic [COLS_P-1:0]          col_parity_err;
    logic [COLS_P-1:0]          col_overflow_err;

    // =========================================================================
    // Input Alignment Pipeline
    // =========================================================================
    logic stall_phase_d, stall_phase_d2;
    logic input_valid_d, input_valid_d2;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            stall_phase_d  <= 1'b0;
            stall_phase_d2 <= 1'b0;
            input_valid_d  <= 1'b0;
            input_valid_d2 <= 1'b0;
        end else begin
            stall_phase_d  <= stall_phase;
            stall_phase_d2 <= stall_phase_d;
            input_valid_d  <= input_valid;
            input_valid_d2 <= input_valid_d;
        end
    end

    // =========================================================================
    // Horizontal Skew Pipelines (for valid and stall_phase)
    // =========================================================================
    // FIX7: Use input_valid directly (not d2) so horizontal skew aligns with data
    logic [COLS_P*2-1:0] valid_h_pipe;
    logic [COLS_P*2-1:0] stall_phase_h_pipe;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_h_pipe       <= '0;
            stall_phase_h_pipe <= '0;
        end else begin
            valid_h_pipe       <= {valid_h_pipe[COLS_P*2-2:0], input_valid};
            stall_phase_h_pipe <= {stall_phase_h_pipe[COLS_P*2-2:0], stall_phase};
        end
    end

    // =========================================================================
    // Vertical Phase Pipelines
    // =========================================================================
    // Vertical phase pipe must delay PE_STAGES cycles per row to stay aligned
    // with psum_valid propagation through the PE pipeline.  Horizontal pipes
    // already use PE_STAGES (2) cycles per column; vertical was only 1 — mismatch
    // caused each row's stall_phase to arrive before its psum_in was ready.
    logic [ROWS_P*PE_STAGES-1:0] stall_phase_v_pipe [COLS_P];
    logic [COLS_P-1:0] current_h_phase_wire;

    // FIX7: Column 0 uses stall_phase directly (matches input_valid timing)
    generate
        for (genvar c = 0; c < COLS_P; c++) begin : gen_h_tap
            if (c == 0) 
                assign current_h_phase_wire[c] = stall_phase;  // FIX7: Direct
            else        
                assign current_h_phase_wire[c] = stall_phase_h_pipe[2*c-1];
        end
    endgenerate

    generate
        for (genvar c = 0; c < COLS_P; c++) begin : gen_col_pipes
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    stall_phase_v_pipe[c] <= '0;
                end else begin
                    stall_phase_v_pipe[c] <= {stall_phase_v_pipe[c][ROWS_P*PE_STAGES-2:0], current_h_phase_wire[c]};
                end
            end
        end
    endgenerate

    // =========================================================================
    // Top Row Initialization
    // =========================================================================
    // FIX7: Column 0 valid must be immediate (no delay) because:
    // - Activation data arrives at row 0 with 0 skew (direct from skew_buffer)
    // - Using input_valid_d2 delays valid by 2 cycles, missing Vec0 entirely
    // - Other columns use horizontal pipe which provides correct skew alignment
    generate
        for (genvar c = 0; c < COLS_P; c++) begin : gen_top_init
            assign psum_v[0][c]   = '0;
            assign parity_v[0][c] = 1'b0;
            
            if (c == 0)
                assign valid_v[0][c] = input_valid;  // FIX7: Direct, no delay
            else
                assign valid_v[0][c] = valid_h_pipe[2*c-1];
        end
    endgenerate

    // =========================================================================
    // Load Enable Decode & Left Activation Connection
    // =========================================================================
    generate
        for (genvar r = 0; r < ROWS_P; r++) begin : gen_misc_connect
            assign act_h[r][0] = act_in[r];
            for (genvar c = 0; c < COLS_P; c++) begin : gen_load_dec
                assign pe_load_en[r][c] = load_en && (load_row_sel == r[$clog2(ROWS_P)-1:0]);
            end
        end
    endgenerate

    // =========================================================================
    // PE Array Instantiation
    // =========================================================================
    generate
        for (genvar r = 0; r < ROWS_P; r++) begin : gen_row
            for (genvar c = 0; c < COLS_P; c++) begin : gen_col
                
                localparam int PE_IDX = r * COLS_P + c;

                // Stall phase selection per PE
                logic pe_stall_phase_node;
                
                if (r == 0) begin : gen_row0_phase
                    assign pe_stall_phase_node = current_h_phase_wire[c];
                end else begin : gen_rowN_phase
                    assign pe_stall_phase_node = stall_phase_v_pipe[c][r*PE_STAGES-1];
                end

                // PE instance signals
                logic pe_zero_wgt, pe_zero_act, pe_overflow, pe_mac_active;
                pe_power_state_e pe_pwr;
                
                pe_v18 #(
                    .W_W              (W_W),
                    .A_W              (A_W),
                    .ACC_W            (ACC_W),
                    .IDX_W            (IDX_W),
                    .WGT_PKT_W        (WGT_PKT_W),
                    .ACT_PKT_W        (ACT_PKT_W),
                    .ENABLE_CLOCK_GATING(ENABLE_ICG),
                    .ENABLE_PARITY    (ENABLE_PAR)
                ) u_pe (
                    .clk              (clk),
                    .rst_n            (rst_n),
                    .scan_enable      (scan_enable),
                    .load_en          (pe_load_en[r][c]),
                    .compute_en       (compute_en),
                    .stall_phase      (pe_stall_phase_node),
                    .mode_dense       (mode_dense),
                    .sparsity_cfg     (sparsity_cfg),
                    .wgt_packet_in    (wgt_in[c]),
                    .wgt_parity_in    (wgt_parity_in[c]),
                    .parity_err_in    (parity_v[r][c]),
                    .parity_err_out   (parity_v[r+1][c]),
                    .act_packet_in    (act_h[r][c]),
                    .act_packet_out   (act_h[r][c+1]),
                    .psum_in          (psum_v[r][c]),
                    .psum_valid_in    (valid_v[r][c]),
                    .psum_out         (psum_v[r+1][c]),
                    .psum_valid_out   (valid_v[r+1][c]),
                    .zero_weight_detected(pe_zero_wgt),
                    .zero_act_detected(pe_zero_act),
                    .overflow_detected(pe_overflow),
                    .power_state      (pe_pwr),
                    .mac_active       (pe_mac_active)
                );
                
                // Map outputs
                assign pe_zero_weight_map[PE_IDX] = pe_zero_wgt;
                assign pe_zero_act_map[PE_IDX]    = pe_zero_act;
                assign pe_overflow_map[PE_IDX]    = pe_overflow;
                assign pe_power_states[r][c]      = pe_pwr;
                assign pe_mac_active_map[PE_IDX]  = pe_mac_active;
            end
        end
    endgenerate

    // =========================================================================
    // Output Assignments
    // =========================================================================
    // FIX7: In dense mode, only output results on Phase 1 (stall_phase=1)
    // Phase 0 outputs would be incomplete (only dense_partial computed)
    // Extract aligned phase from vertical pipe at bottom row
    logic [COLS_P-1:0] output_phase;
    generate
        for (genvar c = 0; c < COLS_P; c++) begin : gen_output_phase
            assign output_phase[c] = stall_phase_v_pipe[c][ROWS_P*PE_STAGES-1];
        end
    endgenerate
    
    generate
        for (genvar c = 0; c < COLS_P; c++) begin : gen_output
            assign psum_out[c]       = psum_v[ROWS_P][c];
            // FIX7: Gate col_valid with phase in dense mode
            assign col_valid[c]      = mode_dense ? (valid_v[ROWS_P][c] && output_phase[c])
                                                  : valid_v[ROWS_P][c];
            assign col_parity_err[c] = parity_v[ROWS_P][c];
        end
        
        // Overflow aggregation per column
        for (genvar c = 0; c < COLS_P; c++) begin : gen_ovf_agg
            logic [ROWS_P-1:0] col_ovf_bits;
            for (genvar r = 0; r < ROWS_P; r++) begin : gen_ovf_bits
                assign col_ovf_bits[r] = pe_overflow_map[r * COLS_P + c];
            end
            assign col_overflow_err[c] = |col_ovf_bits;
        end
    endgenerate

    // FIX7: Gate result_valid with phase in dense mode
    assign result_valid   = mode_dense ? (valid_v[ROWS_P][0] && output_phase[0])
                                       : valid_v[ROWS_P][0];
    assign parity_error   = |col_parity_err;
    assign overflow_error = |col_overflow_err;

    // =========================================================================
    // Active PE Counter
    // =========================================================================
    always_comb begin
        active_pe_count = '0;
        for (int i = 0; i < ROWS_P*COLS_P; i++) begin
            active_pe_count = active_pe_count + pe_mac_active_map[i];
        end
    end

endmodule


// =============================================================================
// MODULE: activation_func_v18
// Description: Post-processing activation functions
// Supports: None (bypass), ReLU, ReLU6, Leaky ReLU
// =============================================================================
module activation_func_v18
    import accel_pkg_v18::*;
#(
    parameter int DATA_W = ACC_WIDTH,
    parameter int COLS_P = COLS
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          enable,
    input  activation_e                   func_sel,
    
    input  logic signed [DATA_W-1:0]      data_in     [COLS_P],
    input  logic [COLS_P-1:0]             valid_in,
    
    output logic signed [DATA_W-1:0]      data_out    [COLS_P],
    output logic [COLS_P-1:0]             valid_out
);

    // ReLU6 threshold (assuming Q8.x format)
    localparam logic signed [DATA_W-1:0] SIX_SCALED = 32'sd6 << 8;
    localparam int LEAKY_ALPHA_SHIFT = 3;  // ~0.125 approximation

    generate
        for (genvar c = 0; c < COLS_P; c++) begin : gen_act
            logic signed [DATA_W-1:0] relu_result;
            logic signed [DATA_W-1:0] relu6_result;
            logic signed [DATA_W-1:0] leaky_result;
            logic signed [DATA_W-1:0] result_mux;
            
            // ReLU: max(0, x)
            assign relu_result = (data_in[c][DATA_W-1]) ? '0 : data_in[c];
            
            // ReLU6: min(max(0, x), 6)
            assign relu6_result = (data_in[c][DATA_W-1]) ? '0 : 
                                  (data_in[c] > SIX_SCALED) ? SIX_SCALED : data_in[c];
            
            // Leaky ReLU: x if x>0, else alpha*x (alpha ≈ 0.125)
            assign leaky_result = (data_in[c][DATA_W-1]) ? 
                                  (data_in[c] >>> LEAKY_ALPHA_SHIFT) : data_in[c];
            
            // Function select mux
            always_comb begin
                case (func_sel)
                    ACT_NONE:       result_mux = data_in[c];
                    ACT_RELU:       result_mux = relu_result;
                    ACT_RELU6:      result_mux = relu6_result;
                    ACT_LEAKY_RELU: result_mux = leaky_result;
                    default:        result_mux = data_in[c];
                endcase
            end
            
            // Pipeline register with valid propagation
            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    data_out[c]  <= '0;
                    valid_out[c] <= 1'b0;
                end else begin
                    // Always propagate valid signal
                    valid_out[c] <= valid_in[c];
                    
                    // Data registered when enabled or valid
                    if (enable || valid_in[c]) begin
                        data_out[c] <= result_mux;
                    end
                end
            end
        end
    endgenerate

endmodule


// =============================================================================
// MODULE: compute_core_v18
// Description: Integrated compute core with skew, array, deskew, activation
// This wraps the systolic array with input/output alignment units
// =============================================================================
module compute_core_v18
    import accel_pkg_v18::*;
#(
    parameter int ROWS_P      = ROWS,
    parameter int COLS_P      = COLS,
    parameter int ACC_W       = ACC_WIDTH,
    parameter int WGT_PKT_W   = WGT_PKT_WIDTH,
    parameter int ACT_PKT_W   = ACT_PKT_WIDTH
)(
    input  logic                              clk,
    input  logic                              rst_n,
    input  logic                              scan_enable,
    
    // Control
    input  logic                              mode_dense,
    input  sparsity_mode_e                    sparsity_cfg,
    input  activation_e                       act_func,
    input  logic                              load_en,
    input  logic                              compute_en,
    input  logic                              drain_en,
    input  logic                              stall_phase,
    input  logic [$clog2(ROWS_P)-1:0]         load_row_sel,
    input  logic                              input_valid,
    input  logic                              clear_buffers,
    
    // Weight Input (all columns)
    input  logic [WGT_PKT_W-1:0]              wgt_in      [COLS_P],
    input  logic [COLS_P-1:0]                 wgt_parity_in,
    
    // Activation Input (single, gets skewed)
    input  logic [ACT_PKT_W-1:0]              act_in,
    
    // Result Output (aligned via deskew)
    output logic signed [ACC_W-1:0]           result_out  [COLS_P],
    output logic [COLS_P-1:0]                 result_valid,
    output logic                              all_results_valid,
    
    // Status
    output logic                              parity_error,
    output logic                              overflow_error,
    output logic [$clog2(ROWS_P*COLS_P+1)-1:0] active_pe_count,
    output logic [ROWS_P*COLS_P-1:0]          pe_mac_active_map
);

    // =========================================================================
    // Internal Signals
    // =========================================================================
    logic [ACT_PKT_W-1:0]      skewed_act      [ROWS_P];
    logic signed [ACC_W-1:0]   array_psum_out  [COLS_P];
    logic [COLS_P-1:0]         array_col_valid;
    logic signed [ACC_W-1:0]   deskewed_psum   [COLS_P];
    logic [COLS_P-1:0]         deskewed_valid;
    logic signed [ACC_W-1:0]   activated_out   [COLS_P];
    logic [COLS_P-1:0]         activated_valid;
    
    // Unused monitoring signals
    logic [ROWS_P*COLS_P-1:0]  pe_zero_weight_map;
    logic [ROWS_P*COLS_P-1:0]  pe_zero_act_map;
    logic [ROWS_P*COLS_P-1:0]  pe_overflow_map;
    pe_power_state_e          pe_power_states [ROWS_P][COLS_P];

    // =========================================================================
    // Input Skew Buffer
    // =========================================================================
    skew_buffer_v18 #(
        .ROWS_P    (ROWS_P),
        .ACT_PKT_W (ACT_PKT_W)
    ) u_skew (
        .clk       (clk),
        .rst_n     (rst_n),
        .enable    (compute_en),
        .clear     (clear_buffers),
        .act_in    (act_in),
        .act_out   (skewed_act)
    );

    // =========================================================================
    // Systolic Array
    // =========================================================================
    systolic_array_v18 #(
        .ROWS_P     (ROWS_P),
        .COLS_P     (COLS_P),
        .ACC_W      (ACC_W),
        .WGT_PKT_W  (WGT_PKT_W),
        .ACT_PKT_W  (ACT_PKT_W),
        .ENABLE_ICG (1),
        .ENABLE_PAR (1)
    ) u_array (
        .clk              (clk),
        .rst_n            (rst_n),
        .scan_enable      (scan_enable),
        .mode_dense       (mode_dense),
        .sparsity_cfg     (sparsity_cfg),
        .load_en          (load_en),
        .compute_en       (compute_en),
        .stall_phase      (stall_phase),
        .load_row_sel     (load_row_sel),
        .input_valid      (input_valid),
        .wgt_in           (wgt_in),
        .wgt_parity_in    (wgt_parity_in),
        .act_in           (skewed_act),
        .psum_out         (array_psum_out),
        .result_valid     (),  // Use col_valid instead
        .col_valid        (array_col_valid),
        .parity_error     (parity_error),
        .overflow_error   (overflow_error),
        .pe_zero_weight_map(pe_zero_weight_map),
        .pe_zero_act_map  (pe_zero_act_map),
        .pe_overflow_map  (pe_overflow_map),
        .pe_mac_active_map(pe_mac_active_map),
        .pe_power_states  (pe_power_states),
        .active_pe_count  (active_pe_count)
    );

    // =========================================================================
    // Output Deskew Buffer
    // =========================================================================
    deskew_buffer_v18 #(
        .COLS_P  (COLS_P),
        .ACC_W   (ACC_W),
        .PE_PIPE (PE_STAGES)
    ) u_deskew (
        .clk       (clk),
        .rst_n     (rst_n),
        .enable    (drain_en),
        .clear     (clear_buffers),
        .psum_in   (array_psum_out),
        .valid_in  (array_col_valid),
        .psum_out  (deskewed_psum),
        .valid_out (deskewed_valid)
    );

    // =========================================================================
    // Activation Function
    // =========================================================================
    activation_func_v18 #(
        .DATA_W (ACC_W),
        .COLS_P (COLS_P)
    ) u_actfunc (
        .clk       (clk),
        .rst_n     (rst_n),
        .enable    (drain_en),
        .func_sel  (act_func),
        .data_in   (deskewed_psum),
        .valid_in  (deskewed_valid),
        .data_out  (activated_out),
        .valid_out (activated_valid)
    );

    // =========================================================================
    // Output Assignment
    // =========================================================================
    assign result_out       = activated_out;
    assign result_valid     = activated_valid;
    assign all_results_valid = &activated_valid;

endmodule