// =============================================================================
// File: 06_top_v18.sv
// Description: V18.4 Accelerator Top-Level Integration (128-bit AXI)
//              - AXI4-Lite CSR interface (for RISC-V integration)
//              - AXI4-Stream data interfaces (128-bit)
//              - Integrated post-processing unit
// Version: 18.4 - Widened to 128-bit AXI-Stream for 2x throughput
// =============================================================================

`timescale 1ns/1ps

module accel_top_v18
    import accel_pkg_v18::*;
#(
    parameter int ROWS_P          = ROWS,
    parameter int COLS_P          = COLS,
    parameter int WEIGHT_FIFO_DEP = WEIGHT_FIFO_DEPTH,
    parameter int OUTPUT_FIFO_DEP = OUTPUT_FIFO_DEPTH,
    parameter bit ENABLE_ICG      = 1,
    parameter bit ENABLE_PARITY   = 1,
    parameter bit ENABLE_POSTPROC = 1  // Enable post-processing unit
)(
    input  logic                          clk,
    input  logic                          rst_n,
    input  logic                          scan_enable,
    
    // =========================================================================
    // AXI4-Lite Configuration Interface (replaces APB)
    // =========================================================================
    // Write Address Channel
    input  logic [AXIL_ADDR_WIDTH-1:0]    s_axil_awaddr,
    input  logic [2:0]                    s_axil_awprot,
    input  logic                          s_axil_awvalid,
    output logic                          s_axil_awready,
    
    // Write Data Channel
    input  logic [AXIL_DATA_WIDTH-1:0]    s_axil_wdata,
    input  logic [AXIL_STRB_WIDTH-1:0]    s_axil_wstrb,
    input  logic                          s_axil_wvalid,
    output logic                          s_axil_wready,
    
    // Write Response Channel
    output logic [1:0]                    s_axil_bresp,
    output logic                          s_axil_bvalid,
    input  logic                          s_axil_bready,
    
    // Read Address Channel
    input  logic [AXIL_ADDR_WIDTH-1:0]    s_axil_araddr,
    input  logic [2:0]                    s_axil_arprot,
    input  logic                          s_axil_arvalid,
    output logic                          s_axil_arready,
    
    // Read Data Channel
    output logic [AXIL_DATA_WIDTH-1:0]    s_axil_rdata,
    output logic [1:0]                    s_axil_rresp,
    output logic                          s_axil_rvalid,
    input  logic                          s_axil_rready,
    
    // =========================================================================
    // AXI4-Stream Weight Input (128-bit)
    // =========================================================================
    input  logic [AXIS_DATA_WIDTH-1:0]    s_axis_weight_tdata,
    input  logic [AXIS_DATA_WIDTH/8-1:0]  s_axis_weight_tkeep,
    input  logic                          s_axis_weight_tlast,
    input  logic [AXIS_USER_WIDTH-1:0]    s_axis_weight_tuser,
    input  logic                          s_axis_weight_tvalid,
    output logic                          s_axis_weight_tready,
    
    // =========================================================================
    // AXI4-Stream Activation Input (128-bit)
    // =========================================================================
    input  logic [AXIS_DATA_WIDTH-1:0]    s_axis_act_tdata,
    input  logic [AXIS_DATA_WIDTH/8-1:0]  s_axis_act_tkeep,
    input  logic                          s_axis_act_tlast,
    input  logic                          s_axis_act_tvalid,
    output logic                          s_axis_act_tready,
    
    // =========================================================================
    // AXI4-Stream Result Output (128-bit)
    // =========================================================================
    output logic [AXIS_DATA_WIDTH-1:0]    m_axis_result_tdata,
    output logic [AXIS_DATA_WIDTH/8-1:0]  m_axis_result_tkeep,
    output logic                          m_axis_result_tlast,
    output logic [AXIS_USER_WIDTH-1:0]    m_axis_result_tuser,
    output logic                          m_axis_result_tvalid,
    input  logic                          m_axis_result_tready,
    
    // =========================================================================
    // Interrupt Output
    // =========================================================================
    output logic                          irq_out,
    
    // =========================================================================
    // Debug/Status Outputs
    // =========================================================================
    output logic                          busy,
    output logic                          done,
    output logic [2:0]                    state_out
);

    // =========================================================================
    // Internal Signal Declarations
    // =========================================================================
    
    // Control signals from CSR
    logic        ctrl_enable;
    logic        ctrl_clear;
    logic        mode_dense;
    sparsity_mode_e sparsity_cfg;
    activation_e activation_fn;
    
    // Post-processing configuration
    postproc_op_e                     pp_op_sel;
    logic signed [PP_BIAS_WIDTH-1:0]  pp_bias [COLS_P];
    logic signed [PP_SCALE_WIDTH-1:0] pp_scale;
    logic [PP_SHIFT_WIDTH-1:0]        pp_shift;
    logic                             pp_round_en;
    logic                             pp_sat_en;
    logic signed [ACC_WIDTH-1:0]      pp_sat_max;
    logic signed [ACC_WIDTH-1:0]      pp_sat_min;
    
    // Compute controller signals
    logic        load_en;
    logic        compute_en;
    logic        drain_en;
    logic        stall_phase;
    logic [$clog2(ROWS_P)-1:0] load_row_sel;
    logic        input_valid;
    
    // Weight AXIS RX to buffer signals
    logic                          wgt_rx_tile_start;
    logic                          wgt_rx_row_valid;
    logic [WGT_PKT_WIDTH-1:0]      wgt_rx_data [COLS_P];
    logic [COLS_P-1:0]             wgt_rx_parity;
    logic                          wgt_rx_tile_done;
    logic                          wgt_rx_tile_ready;
    sparsity_mode_e                wgt_rx_sparsity_mode;
    
    // Weight buffer to array signals
    logic                          wgt_buf_tile_start;
    logic                          wgt_buf_row_next;
    logic [WGT_PKT_WIDTH-1:0]      wgt_buf_data [COLS_P];
    logic [COLS_P-1:0]             wgt_buf_parity;
    logic                          wgt_buf_row_valid;
    logic                          wgt_buf_last_row;
    logic                          wgt_buf_tile_done;
    logic                          wgt_buf_tile_ready;
    
    // Activation path signals
    logic [ACT_PKT_WIDTH-1:0]      act_data;
    logic                          act_valid;
    logic                          act_ready;
    logic                          act_last;
    
    // Array signals
    logic [ACT_PKT_WIDTH-1:0]      array_act_in [ROWS_P];
    logic signed [ACC_WIDTH-1:0]   array_psum_out [COLS_P];
    logic                          array_result_valid;
    logic [COLS_P-1:0]             array_col_valid;
    logic                          array_parity_error;
    logic                          array_overflow_error;
    logic [ROWS_P*COLS_P-1:0]      pe_zero_weight_map;
    logic [ROWS_P*COLS_P-1:0]      pe_zero_act_map;
    logic [ROWS_P*COLS_P-1:0]      pe_overflow_map;
    logic [ROWS_P*COLS_P-1:0]      pe_mac_active_map;
    pe_power_state_e               pe_power_states [ROWS_P][COLS_P];
    logic [$clog2(ROWS_P*COLS_P+1)-1:0] active_pe_count;
    
    // Deskew buffer signals
    logic signed [ACC_WIDTH-1:0]   deskew_psum_out [COLS_P];
    logic [COLS_P-1:0]             deskew_valid_out;
    
    // Activation function signals
    logic signed [ACC_WIDTH-1:0]   actfn_data_out [COLS_P];
    logic [COLS_P-1:0]             actfn_valid_out;
    
    // Post-processing signals
    logic signed [ACC_WIDTH-1:0]   postproc_data_out [COLS_P];
    logic [COLS_P-1:0]             postproc_valid_out;
    logic [COLS_P-1:0]             postproc_sat_flag;
    
    // Output FIFO input selection (after postproc or actfn)
    logic signed [ACC_WIDTH-1:0]   ofifo_data_in [COLS_P];
    logic [COLS_P-1:0]             ofifo_valid_in;
    
    // Output FIFO signals
    logic signed [ACC_WIDTH-1:0]   ofifo_data_out [COLS_P];
    logic                          ofifo_valid_out;
    logic                          ofifo_read_en;
    logic                          ofifo_empty;
    logic                          ofifo_full;
    logic                          ofifo_almost_full;
    logic [$clog2(OUTPUT_FIFO_DEP+1)-1:0] ofifo_level;
    
    // Result TX signals
    logic                          result_read;
    logic                          drain_done;
    
    // Drain control signals
    logic                          drain_start;
    logic [15:0]                   drain_count;
    logic [15:0]                   drain_vector_count;
    
    // FIX: Enable result drain during BOTH streaming and drain phases
    // This allows concurrent result output while activations are still streaming
    assign drain_start = compute_en;  // Active during both S_STREAM and S_DRAIN
    assign drain_count = drain_vector_count;
    
    // FIFO status for CSR
    logic [4:0] wfifo_level, afifo_level, rfifo_level;
    logic       wfifo_full, wfifo_empty;
    logic       afifo_full, afifo_empty;
    logic       rfifo_full, rfifo_empty;
    
    // =========================================================================
    // Weight Tile Buffer
    // =========================================================================
    logic wgt_buf_wr_done;
    logic wgt_buf_can_accept;  // V18.3: For prefetch
    logic wgt_prefetch_start;  // V18.3: Prefetch trigger from controller
    
    weight_tile_buffer_v18 #(
        .TILE_DEPTH (WEIGHT_FIFO_DEP),
        .ROWS_P     (ROWS_P),
        .COLS_P     (COLS_P)
    ) u_weight_buffer (
        .clk            (clk),
        .rst_n          (rst_n),
        .clear          (ctrl_clear),
        // Write side - from AXIS RX
        .wr_start       (wgt_rx_tile_start),
        .wr_valid       (wgt_rx_row_valid),
        .wr_data        (wgt_rx_data),
        .wr_parity      (wgt_rx_parity),
        .wr_ready       (wgt_rx_tile_ready),
        .wr_done        (wgt_buf_wr_done),
        // Read side - to array
        .rd_start       (wgt_buf_tile_start),
        .rd_next_row    (wgt_buf_row_next),
        .rd_data        (wgt_buf_data),
        .rd_parity      (wgt_buf_parity),
        .rd_row         (),
        .rd_valid       (wgt_buf_row_valid),
        .rd_last_row    (wgt_buf_last_row),
        .rd_done        (wgt_buf_tile_done),
        .can_accept_tile(wgt_buf_can_accept),  // V18.3: For prefetch
        .has_tile_ready (wgt_buf_tile_ready),
        .tile_count     (),
        .fifo_full      (wfifo_full),
        .fifo_empty     (wfifo_empty)
    );
    
    assign wfifo_level = '0;
    
    // =========================================================================
    // AXIS Interface Wrapper (128-bit)
    // =========================================================================
    axis_interface_wrapper_v18 #(
        .ROWS_P(ROWS_P),
        .COLS_P(COLS_P)
    ) u_axis_if (
        .clk                 (clk),
        .rst_n               (rst_n),
        .clear               (ctrl_clear),
        .enable              (ctrl_enable),
        
        // Weight AXIS (128-bit)
        .s_axis_weight_tdata (s_axis_weight_tdata),
        .s_axis_weight_tkeep (s_axis_weight_tkeep),
        .s_axis_weight_tlast (s_axis_weight_tlast),
        .s_axis_weight_tuser (s_axis_weight_tuser),
        .s_axis_weight_tvalid(s_axis_weight_tvalid),
        .s_axis_weight_tready(s_axis_weight_tready),
        
        // Activation AXIS (128-bit)
        .s_axis_act_tdata    (s_axis_act_tdata),
        .s_axis_act_tkeep    (s_axis_act_tkeep),
        .s_axis_act_tlast    (s_axis_act_tlast),
        .s_axis_act_tvalid   (s_axis_act_tvalid),
        .s_axis_act_tready   (s_axis_act_tready),
        
        // Result AXIS (128-bit)
        .m_axis_result_tdata (m_axis_result_tdata),
        .m_axis_result_tkeep (m_axis_result_tkeep),
        .m_axis_result_tlast (m_axis_result_tlast),
        .m_axis_result_tuser (m_axis_result_tuser),
        .m_axis_result_tvalid(m_axis_result_tvalid),
        .m_axis_result_tready(m_axis_result_tready),
        
        // Weight internal interfaces
        .wgt_tile_start      (wgt_rx_tile_start),
        .wgt_row_valid       (wgt_rx_row_valid),
        .wgt_data            (wgt_rx_data),
        .wgt_parity          (wgt_rx_parity),
        .wgt_tile_done       (wgt_rx_tile_done),
        .wgt_tile_ready      (wgt_rx_tile_ready),
        .sparsity_mode       (wgt_rx_sparsity_mode),
        
        .act_data            (act_data),
        .act_valid           (act_valid),
        .act_ready           (act_ready),
        .act_last            (act_last),
        
        .result_data         (ofifo_data_out),
        .result_valid        (ofifo_valid_out),
        .result_read         (result_read),
        .drain_start         (drain_start),
        .drain_count         (drain_count),
        .drain_done          (drain_done),
        
        // Status
        .weight_rx_active    (),
        .act_rx_active       (),
        .result_tx_active    ()
    );
    
    // =========================================================================
    // Skew Buffer (Activation Input)
    // =========================================================================
    skew_buffer_v18 #(
        .ROWS_P    (ROWS_P),
        .ACT_PKT_W (ACT_PKT_WIDTH)
    ) u_skew (
        .clk     (clk),
        .rst_n   (rst_n),
        .enable  (compute_en),
        .clear   (u_control.ctrl_clear_out),
        .act_in  (act_data),
        .act_out (array_act_in)
    );
    
    // =========================================================================
    // Systolic Array
    // =========================================================================
    systolic_array_v18 #(
        .ROWS_P     (ROWS_P),
        .COLS_P     (COLS_P),
        .ENABLE_ICG (ENABLE_ICG),
        .ENABLE_PAR (ENABLE_PARITY)
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
        .wgt_in           (wgt_buf_data),
        .wgt_parity_in    (wgt_buf_parity),
        .act_in           (array_act_in),
        .psum_out         (array_psum_out),
        .result_valid     (array_result_valid),
        .col_valid        (array_col_valid),
        .parity_error     (array_parity_error),
        .overflow_error   (array_overflow_error),
        .pe_zero_weight_map(pe_zero_weight_map),
        .pe_zero_act_map  (pe_zero_act_map),
        .pe_overflow_map  (pe_overflow_map),
        .pe_mac_active_map(pe_mac_active_map),
        .pe_power_states  (pe_power_states),
        .active_pe_count  (active_pe_count)
    );
    
    // =========================================================================
    // Deskew Buffer (Output Alignment)
    // =========================================================================
    deskew_buffer_v18 #(
        .COLS_P  (COLS_P),
        .ACC_W   (ACC_WIDTH),
        .PE_PIPE (PE_STAGES)
    ) u_deskew (
        .clk       (clk),
        .rst_n     (rst_n),
        .enable    (compute_en || drain_en),
        .clear     (u_control.ctrl_clear_out),
        .psum_in   (array_psum_out),
        .valid_in  (array_col_valid),
        .psum_out  (deskew_psum_out),
        .valid_out (deskew_valid_out)
    );
    
    // =========================================================================
    // Activation Function
    // =========================================================================
    activation_func_v18 #(
        .DATA_W (ACC_WIDTH),
        .COLS_P (COLS_P)
    ) u_actfn (
        .clk       (clk),
        .rst_n     (rst_n),
        .enable    (compute_en || drain_en),
        .func_sel  (activation_fn),
        .data_in   (deskew_psum_out),
        .valid_in  (deskew_valid_out),
        .data_out  (actfn_data_out),
        .valid_out (actfn_valid_out)
    );
    
    // =========================================================================
    // Post-Processing Unit
    // =========================================================================
    generate
        if (ENABLE_POSTPROC) begin : gen_postproc
            vector_postproc_v18 #(
                .COLS_P  (COLS_P),
                .DATA_W  (ACC_WIDTH),
                .BIAS_W  (PP_BIAS_WIDTH),
                .SCALE_W (PP_SCALE_WIDTH),
                .SHIFT_W (PP_SHIFT_WIDTH)
            ) u_postproc (
                .clk       (clk),
                .rst_n     (rst_n),
                .enable    (compute_en || drain_en),
                
                // Input from activation function
                .data_in   (actfn_data_out),
                .valid_in  (actfn_valid_out),
                
                // Configuration from CSR
                .op_sel    (pp_op_sel),
                .bias      (pp_bias),
                .scale     (pp_scale),
                .shift     (pp_shift),
                .round_en  (pp_round_en),
                .sat_en    (pp_sat_en),
                .sat_max   (pp_sat_max),
                .sat_min   (pp_sat_min),
                
                // Output
                .data_out  (postproc_data_out),
                .valid_out (postproc_valid_out),
                .sat_flag  (postproc_sat_flag)
            );
            
            // Route post-processed data to output FIFO
            assign ofifo_data_in  = postproc_data_out;
            assign ofifo_valid_in = postproc_valid_out;
        end else begin : gen_no_postproc
            // Bypass post-processing
            assign ofifo_data_in  = actfn_data_out;
            assign ofifo_valid_in = actfn_valid_out;
            assign postproc_sat_flag = '0;
        end
    endgenerate
    
    // =========================================================================
    // Output Collector FIFO
    // =========================================================================
    output_collector_fifo_v18 #(
        .DEPTH  (OUTPUT_FIFO_DEP),
        .DATA_W (ACC_WIDTH),
        .COLS_P (COLS_P)
    ) u_output_fifo (
        .clk          (clk),
        .rst_n        (rst_n),
        .clear        (ctrl_clear),
        .data_in      (ofifo_data_in),
        .valid_in     (ofifo_valid_in),
        .ready_out    (),
        .data_out     (ofifo_data_out),
        .valid_out    (ofifo_valid_out),
        .read_en      (result_read),
        .empty        (ofifo_empty),
        .full         (ofifo_full),
        .almost_full  (ofifo_almost_full),
        .level        (ofifo_level),
        .overflow_err (),
        .underflow_err()
    );
    
    // FIX: Avoid negative replication when OUTPUT_FIFO_DEP > 16
    localparam int OFIFO_LEVEL_WIDTH = $clog2(OUTPUT_FIFO_DEP+1);
    generate
        if (OFIFO_LEVEL_WIDTH <= 5) begin : gen_rfifo_pad
            assign rfifo_level = {{(5-OFIFO_LEVEL_WIDTH){1'b0}}, ofifo_level};
        end else begin : gen_rfifo_trunc
            assign rfifo_level = ofifo_level[4:0];  // Truncate to 5 bits
        end
    endgenerate
    assign rfifo_full  = ofifo_full;
    assign rfifo_empty = ofifo_empty;
    
    // Activation FIFO status
    assign afifo_level = '0;
    assign afifo_full  = 1'b0;
    assign afifo_empty = !act_valid;
    
    // =========================================================================
    // Control Top (AXI-Lite Interface)
    // =========================================================================
    control_top_v18 #(
        .ROWS_P(ROWS_P),
        .COLS_P(COLS_P)
    ) u_control (
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
        
        // Weight interface
        .wgt_tile_ready  (wgt_buf_tile_ready),
        .wgt_can_accept  (wgt_buf_can_accept),   // V18.3: For prefetch
        .wgt_tile_start  (wgt_buf_tile_start),
        .wgt_prefetch_start(wgt_prefetch_start), // V18.3: Prefetch trigger
        .wgt_row_next    (wgt_buf_row_next),
        .wgt_row_valid   (wgt_buf_row_valid),
        .wgt_last_row    (wgt_buf_last_row),
        .wgt_tile_done   (wgt_buf_tile_done),
        
        // Activation interface
        .act_ready       (act_ready),
        .act_valid       (act_valid),
        .act_last        (act_last),
        
        // Array control
        .load_en         (load_en),
        .compute_en      (compute_en),
        .drain_en        (drain_en),
        .stall_phase     (stall_phase),
        .load_row_sel    (load_row_sel),
        .input_valid     (input_valid),
        .mode_dense      (mode_dense),
        .sparsity_cfg    (sparsity_cfg),
        .activation_fn   (activation_fn),
        
        // Post-processing config
        .pp_op_sel       (pp_op_sel),
        .pp_bias         (pp_bias),
        .pp_scale        (pp_scale),
        .pp_shift        (pp_shift),
        .pp_round_en     (pp_round_en),
        .pp_sat_en       (pp_sat_en),
        .pp_sat_max      (pp_sat_max),
        .pp_sat_min      (pp_sat_min),
        
        // Result interface
        .result_valid    (ofifo_valid_out),
        .result_read     (ofifo_read_en),
        .result_fifo_full(ofifo_full),
        
        // Drain vector count
        .drain_vector_count(drain_vector_count),
        
        // FIFO status
        .wfifo_level     (wfifo_level),
        .wfifo_full      (wfifo_full),
        .wfifo_empty     (wfifo_empty),
        .afifo_level     (afifo_level),
        .afifo_full      (afifo_full),
        .afifo_empty     (afifo_empty),
        .rfifo_level     (rfifo_level),
        .rfifo_full      (rfifo_full),
        .rfifo_empty     (rfifo_empty),
        
        // Performance monitoring
        .pe_zero_weight_map(pe_zero_weight_map),
        .pe_zero_act_map  (pe_zero_act_map),
        .pe_mac_active_map(pe_mac_active_map),
        
        // IRQ
      .irq_out         (irq_out),
      .ctrl_clear_out(ctrl_clear)
      
    );
    
    // =========================================================================
    // Control Signal Extraction
    // =========================================================================
    // ctrl_enable and ctrl_clear are internal to control_top
    // We expose them via a simple always-on for now
    assign ctrl_enable = 1'b1;
    //assign ctrl_clear  = 1'b0;
    
    // =========================================================================
    // Status Outputs
    // =========================================================================
    assign busy = !ofifo_empty || compute_en;
    assign done = ofifo_empty && !compute_en;
    assign state_out = compute_en ? 3'b010 : (drain_en ? 3'b011 : 3'b000);

endmodule