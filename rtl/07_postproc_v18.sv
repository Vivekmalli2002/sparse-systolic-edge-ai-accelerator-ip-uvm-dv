// =============================================================================
// File: 07_postproc_v18.sv
// Description: V18.3 Vector Post-Processing Unit with Scalable Bias Memory
//              Supports: Bias addition, Scale+Shift, Full Requantization
//              3-stage pipeline: Bias -> Scale -> Shift+Round+Saturate
//              NEW: Scalable bias memory supports any array size (up to 256 cols)
// Version: 18.3
// =============================================================================

`timescale 1ns/1ps

// =============================================================================
// MODULE: postproc_bias_mem_v18
// Description: Scalable bias memory for post-processing unit
//              Supports any array size up to 256 columns
//              Loaded via AXI-Lite writes to CSR_PP_BIAS_MEM
// =============================================================================
module postproc_bias_mem_v18
    import accel_pkg_v18::*;
#(
    parameter int COLS_P = 32,
    parameter int BIAS_WIDTH = PP_BIAS_WIDTH
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          clear,
    
    // Single write interface (from CSR - for backwards compatibility)
    input  logic                          wr_en,
    input  logic [$clog2(COLS_P)-1:0]     wr_addr,
    input  logic signed [BIAS_WIDTH-1:0]  wr_data,
    
    // Bulk write interface (2 biases per write, faster loading)
    input  logic                          bulk_wr_en,
    input  logic [$clog2((COLS_P+1)/2)-1:0] bulk_wr_addr,
    input  logic [31:0]                   bulk_wr_data,  // {bias[odd], bias[even]}
    
    // Legacy CSR interface (8 registers, 16 biases max)
    input  logic                          legacy_wr_en,
    input  logic [2:0]                    legacy_wr_reg,   // 0-7
    input  logic [31:0]                   legacy_wr_data,  // 2 packed biases
    
    // Read interface (all biases for parallel PE access)
    output logic signed [BIAS_WIDTH-1:0]  bias_out [COLS_P]
);

    // =========================================================================
    // Bias Storage
    // =========================================================================
    logic signed [BIAS_WIDTH-1:0] bias_mem [COLS_P];
    
    // Compute column indices
    logic [$clog2(COLS_P):0] bulk_col0, bulk_col1;
    logic [$clog2(COLS_P):0] legacy_col0, legacy_col1;
    
    assign bulk_col0   = {1'b0, bulk_wr_addr, 1'b0};  // bulk_wr_addr * 2
    assign bulk_col1   = {1'b0, bulk_wr_addr, 1'b0} + 1;  // bulk_wr_addr * 2 + 1
    assign legacy_col0 = {1'b0, legacy_wr_reg, 1'b0};  // legacy_wr_reg * 2
    assign legacy_col1 = {1'b0, legacy_wr_reg, 1'b0} + 1;  // legacy_wr_reg * 2 + 1
    
    // =========================================================================
    // Write Logic - Priority: bulk > single > legacy
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < COLS_P; i++)
                bias_mem[i] <= '0;
        end else if (clear) begin
            for (int i = 0; i < COLS_P; i++)
                bias_mem[i] <= '0;
        end else if (bulk_wr_en) begin
            // Bulk write: 2 biases per 32-bit word
            if (bulk_col0 < COLS_P)
                bias_mem[bulk_col0[$clog2(COLS_P)-1:0]] <= bulk_wr_data[BIAS_WIDTH-1:0];
            if (bulk_col1 < COLS_P)
                bias_mem[bulk_col1[$clog2(COLS_P)-1:0]] <= bulk_wr_data[2*BIAS_WIDTH-1:BIAS_WIDTH];
        end else if (wr_en) begin
            // Single bias write
            if (wr_addr < COLS_P)
                bias_mem[wr_addr] <= wr_data;
        end else if (legacy_wr_en) begin
            // Legacy CSR register write (backwards compatible)
            if (legacy_col0 < COLS_P)
                bias_mem[legacy_col0[$clog2(COLS_P)-1:0]] <= legacy_wr_data[BIAS_WIDTH-1:0];
            if (legacy_col1 < COLS_P)
                bias_mem[legacy_col1[$clog2(COLS_P)-1:0]] <= legacy_wr_data[2*BIAS_WIDTH-1:BIAS_WIDTH];
        end
    end
    
    // =========================================================================
    // Output - All biases available in parallel
    // =========================================================================
    generate
        for (genvar i = 0; i < COLS_P; i++) begin : gen_bias_out
            assign bias_out[i] = bias_mem[i];
        end
    endgenerate

endmodule


// =============================================================================
// MODULE: vector_postproc_v18
// Description: Per-column post-processing with configurable operations
//              Now uses scalable bias memory instead of fixed CSR registers
// =============================================================================
module vector_postproc_v18
    import accel_pkg_v18::*;
#(
    parameter int COLS_P   = COLS,
    parameter int DATA_W   = ACC_WIDTH,
    parameter int BIAS_W   = PP_BIAS_WIDTH,
    parameter int SCALE_W  = PP_SCALE_WIDTH,
    parameter int SHIFT_W  = PP_SHIFT_WIDTH
)(
    input  logic                              clk,
    input  logic                              rst_n,
    input  logic                              enable,
    
    // Input data (from activation function)
    input  logic signed [DATA_W-1:0]          data_in [COLS_P],
    input  logic [COLS_P-1:0]                 valid_in,
    
    // Configuration
    input  postproc_op_e                      op_sel,
    input  logic signed [BIAS_W-1:0]          bias [COLS_P],
    input  logic signed [SCALE_W-1:0]         scale,
    input  logic [SHIFT_W-1:0]                shift,
    input  logic                              round_en,
    input  logic                              sat_en,
    input  logic signed [DATA_W-1:0]          sat_max,
    input  logic signed [DATA_W-1:0]          sat_min,
    
    // Output data
    output logic signed [DATA_W-1:0]          data_out [COLS_P],
    output logic [COLS_P-1:0]                 valid_out,
    output logic [COLS_P-1:0]                 sat_flag
);

    // =========================================================================
    // Extended Width for Intermediate Calculations
    // =========================================================================
    localparam int EXT_W = DATA_W + SCALE_W + 1;

    // =========================================================================
    // Pipeline Stage 1: Bias Addition
    // =========================================================================
    logic signed [DATA_W-1:0]   s1_data [COLS_P];
    logic [COLS_P-1:0]          s1_valid;
    postproc_op_e               s1_op;
    logic                       s1_round_en;
    logic                       s1_sat_en;
    logic [SHIFT_W-1:0]         s1_shift;
    logic signed [SCALE_W-1:0]  s1_scale;
    logic signed [DATA_W-1:0]   s1_sat_max, s1_sat_min;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1_valid    <= '0;
            s1_op       <= PP_NONE;
            s1_round_en <= 1'b0;
            s1_sat_en   <= 1'b0;
            s1_shift    <= '0;
            s1_scale    <= '0;
            s1_sat_max  <= '0;
            s1_sat_min  <= '0;
            for (int c = 0; c < COLS_P; c++)
                s1_data[c] <= '0;
        end else if (enable) begin
            s1_valid    <= valid_in;
            s1_op       <= op_sel;
            s1_round_en <= round_en;
            s1_sat_en   <= sat_en;
            s1_shift    <= shift;
            s1_scale    <= scale;
            s1_sat_max  <= sat_max;
            s1_sat_min  <= sat_min;
            
            for (int c = 0; c < COLS_P; c++) begin
                logic signed [DATA_W:0] sum;
                logic signed [DATA_W-1:0] bias_ext;
                
                // Sign-extend bias to DATA_W
                bias_ext = $signed(bias[c]);
                sum = data_in[c] + bias_ext;
                
                case (op_sel)
                    PP_BIAS_ADD, PP_REQUANT, PP_BIAS_SCALE: begin
                        // Saturating bias addition
                        if (sat_en && sum > $signed({1'b0, sat_max}))
                            s1_data[c] <= sat_max;
                        else if (sat_en && sum < $signed({1'b1, sat_min[DATA_W-2:0]}))
                            s1_data[c] <= sat_min;
                        else
                            s1_data[c] <= sum[DATA_W-1:0];
                    end
                    default: begin
                        s1_data[c] <= data_in[c];
                    end
                endcase
            end
        end else begin
            s1_valid <= '0;
        end
    end

    // =========================================================================
    // Pipeline Stage 2: Scale Multiplication
    // =========================================================================
    logic signed [EXT_W-1:0]    s2_data [COLS_P];
    logic [COLS_P-1:0]          s2_valid;
    postproc_op_e               s2_op;
    logic                       s2_round_en;
    logic                       s2_sat_en;
    logic [SHIFT_W-1:0]         s2_shift;
    logic signed [DATA_W-1:0]   s2_sat_max, s2_sat_min;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s2_valid    <= '0;
            s2_op       <= PP_NONE;
            s2_round_en <= 1'b0;
            s2_sat_en   <= 1'b0;
            s2_shift    <= '0;
            s2_sat_max  <= '0;
            s2_sat_min  <= '0;
            for (int c = 0; c < COLS_P; c++)
                s2_data[c] <= '0;
        end else if (enable) begin
            s2_valid    <= s1_valid;
            s2_op       <= s1_op;
            s2_round_en <= s1_round_en;
            s2_sat_en   <= s1_sat_en;
            s2_shift    <= s1_shift;
            s2_sat_max  <= s1_sat_max;
            s2_sat_min  <= s1_sat_min;
            
            for (int c = 0; c < COLS_P; c++) begin
                case (s1_op)
                    PP_SCALE_SHIFT, PP_REQUANT, PP_BIAS_SCALE: begin
                        // Full-precision multiply
                        s2_data[c] <= s1_data[c] * s1_scale;
                    end
                    default: begin
                        // Sign-extend for bypass
                        s2_data[c] <= {{(EXT_W-DATA_W){s1_data[c][DATA_W-1]}}, s1_data[c]};
                    end
                endcase
            end
        end else begin
            s2_valid <= '0;
        end
    end

    // =========================================================================
    // Pipeline Stage 3: Shift + Round + Saturate
    // =========================================================================
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= '0;
            sat_flag  <= '0;
            for (int c = 0; c < COLS_P; c++)
                data_out[c] <= '0;
        end else if (enable) begin
            valid_out <= s2_valid;
            
            for (int c = 0; c < COLS_P; c++) begin
                logic signed [EXT_W-1:0] shifted;
                logic signed [EXT_W-1:0] rounded;
                logic signed [DATA_W-1:0] result;
                logic sat_occurred;
                
                sat_occurred = 1'b0;
                
                case (s2_op)
                    PP_SCALE_SHIFT, PP_REQUANT, PP_BIAS_SCALE: begin
                        // Rounding: add 0.5 before shift
                        if (s2_round_en && s2_shift > 0)
                            rounded = s2_data[c] + (EXT_W'(1) << (s2_shift - 1));
                        else
                            rounded = s2_data[c];
                        
                        // Arithmetic right shift
                        shifted = rounded >>> s2_shift;
                        
                        // Saturation check
                        if (s2_sat_en) begin
                            if (shifted > $signed({{(EXT_W-DATA_W){1'b0}}, s2_sat_max})) begin
                                result = s2_sat_max;
                                sat_occurred = 1'b1;
                            end else if (shifted < $signed({{(EXT_W-DATA_W){1'b1}}, s2_sat_min})) begin
                                result = s2_sat_min;
                                sat_occurred = 1'b1;
                            end else begin
                                result = shifted[DATA_W-1:0];
                            end
                        end else begin
                            result = shifted[DATA_W-1:0];
                        end
                        
                        data_out[c] <= result;
                        sat_flag[c] <= sat_occurred;
                    end
                    default: begin
                        data_out[c] <= s2_data[c][DATA_W-1:0];
                        sat_flag[c] <= 1'b0;
                    end
                endcase
            end
        end else begin
            valid_out <= '0;
            sat_flag  <= '0;
        end
    end

endmodule


// =============================================================================
// MODULE: requantize_unit_v18
// Description: INT32 to INT8 requantization with per-channel parameters
// =============================================================================
module requantize_unit_v18
    import accel_pkg_v18::*;
#(
    parameter int COLS_P   = COLS,
    parameter int IN_W     = ACC_WIDTH,
    parameter int OUT_W    = A_WIDTH,
    parameter int SCALE_W  = PP_SCALE_WIDTH,
    parameter int SHIFT_W  = PP_SHIFT_WIDTH
)(
    input  logic                              clk,
    input  logic                              rst_n,
    input  logic                              enable,
    
    // Input (INT32)
    input  logic signed [IN_W-1:0]            data_in [COLS_P],
    input  logic [COLS_P-1:0]                 valid_in,
    
    // Per-channel parameters
    input  logic signed [SCALE_W-1:0]         scale [COLS_P],
    input  logic [SHIFT_W-1:0]                shift [COLS_P],
    input  logic signed [OUT_W-1:0]           zero_point [COLS_P],
    
    // Output (INT8)
    output logic signed [OUT_W-1:0]           data_out [COLS_P],
    output logic [COLS_P-1:0]                 valid_out
);

    localparam logic signed [OUT_W-1:0] INT8_MAX = 8'sd127;
    localparam logic signed [OUT_W-1:0] INT8_MIN = -8'sd128;
    localparam int MUL_W = IN_W + SCALE_W;
    
    // Stage 1: Multiply
    logic signed [MUL_W-1:0] scaled [COLS_P];
    logic [COLS_P-1:0] valid_s1;
    logic [SHIFT_W-1:0] shift_s1 [COLS_P];
    logic signed [OUT_W-1:0] zp_s1 [COLS_P];
    
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_s1 <= '0;
            for (int c = 0; c < COLS_P; c++) begin
                scaled[c]   <= '0;
                shift_s1[c] <= '0;
                zp_s1[c]    <= '0;
            end
        end else if (enable) begin
            valid_s1 <= valid_in;
            for (int c = 0; c < COLS_P; c++) begin
                scaled[c]   <= data_in[c] * scale[c];
                shift_s1[c] <= shift[c];
                zp_s1[c]    <= zero_point[c];
            end
        end else begin
            valid_s1 <= '0;
        end
    end
    
    // Stage 2: Shift, add zero point, saturate
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            valid_out <= '0;
            for (int c = 0; c < COLS_P; c++)
                data_out[c] <= '0;
        end else if (enable) begin
            valid_out <= valid_s1;
            
            for (int c = 0; c < COLS_P; c++) begin
                logic signed [IN_W-1:0] shifted;
                logic signed [IN_W-1:0] with_zp;
                
                // Round and shift
                if (shift_s1[c] > 0)
                    shifted = (scaled[c] + (MUL_W'(1) << (shift_s1[c] - 1))) >>> shift_s1[c];
                else
                    shifted = scaled[c][IN_W-1:0];
                
                // Add zero point (sign-extended)
                with_zp = shifted + $signed({{(IN_W-OUT_W){zp_s1[c][OUT_W-1]}}, zp_s1[c]});
                
                // Saturate to INT8
                if (with_zp > $signed({{(IN_W-OUT_W){1'b0}}, INT8_MAX}))
                    data_out[c] <= INT8_MAX;
                else if (with_zp < $signed({{(IN_W-OUT_W){1'b1}}, INT8_MIN}))
                    data_out[c] <= INT8_MIN;
                else
                    data_out[c] <= with_zp[OUT_W-1:0];
            end
        end else begin
            valid_out <= '0;
        end
    end

endmodule


// =============================================================================
// MODULE: postproc_top_v18
// Description: Post-processing wrapper with integrated bias memory
//              Provides unified interface for CSR and datapath
// =============================================================================
module postproc_top_v18
    import accel_pkg_v18::*;
#(
    parameter int COLS_P = COLS
)(
    input  logic                              clk,
    input  logic                              rst_n,
    input  logic                              clear,
    input  logic                              enable,
    
    // Bias memory write interface (from CSR block)
    input  logic                              bias_wr_en,
    input  logic [$clog2(COLS_P)-1:0]         bias_wr_addr,
    input  logic signed [PP_BIAS_WIDTH-1:0]   bias_wr_data,
    
    // Bulk bias write (2 biases per write)
    input  logic                              bias_bulk_wr_en,
    input  logic [$clog2((COLS_P+1)/2)-1:0]   bias_bulk_wr_addr,
    input  logic [31:0]                       bias_bulk_wr_data,
    
    // Legacy CSR register write (backwards compatible with 8-register interface)
    input  logic                              bias_legacy_wr_en,
    input  logic [2:0]                        bias_legacy_wr_reg,
    input  logic [31:0]                       bias_legacy_wr_data,
    
    // Configuration
    input  postproc_op_e                      op_sel,
    input  logic signed [PP_SCALE_WIDTH-1:0]  scale,
    input  logic [PP_SHIFT_WIDTH-1:0]         shift,
    input  logic                              round_en,
    input  logic                              sat_en,
    input  logic signed [ACC_WIDTH-1:0]       sat_max,
    input  logic signed [ACC_WIDTH-1:0]       sat_min,
    
    // Input data
    input  logic signed [ACC_WIDTH-1:0]       data_in [COLS_P],
    input  logic [COLS_P-1:0]                 valid_in,
    
    // Output data
    output logic signed [ACC_WIDTH-1:0]       data_out [COLS_P],
    output logic [COLS_P-1:0]                 valid_out,
    output logic [COLS_P-1:0]                 sat_flag
);

    // =========================================================================
    // Bias Memory Instance
    // =========================================================================
    logic signed [PP_BIAS_WIDTH-1:0] bias_values [COLS_P];
    
    postproc_bias_mem_v18 #(
        .COLS_P(COLS_P),
        .BIAS_WIDTH(PP_BIAS_WIDTH)
    ) u_bias_mem (
        .clk            (clk),
        .rst_n          (rst_n),
        .clear          (clear),
        .wr_en          (bias_wr_en),
        .wr_addr        (bias_wr_addr),
        .wr_data        (bias_wr_data),
        .bulk_wr_en     (bias_bulk_wr_en),
        .bulk_wr_addr   (bias_bulk_wr_addr),
        .bulk_wr_data   (bias_bulk_wr_data),
        .legacy_wr_en   (bias_legacy_wr_en),
        .legacy_wr_reg  (bias_legacy_wr_reg),
        .legacy_wr_data (bias_legacy_wr_data),
        .bias_out       (bias_values)
    );
    
    // =========================================================================
    // Post-Processing Unit Instance
    // =========================================================================
    vector_postproc_v18 #(
        .COLS_P(COLS_P)
    ) u_postproc (
        .clk        (clk),
        .rst_n      (rst_n),
        .enable     (enable),
        .data_in    (data_in),
        .valid_in   (valid_in),
        .op_sel     (op_sel),
        .bias       (bias_values),
        .scale      (scale),
        .shift      (shift),
        .round_en   (round_en),
        .sat_en     (sat_en),
        .sat_max    (sat_max),
        .sat_min    (sat_min),
        .data_out   (data_out),
        .valid_out  (valid_out),
        .sat_flag   (sat_flag)
    );

endmodule