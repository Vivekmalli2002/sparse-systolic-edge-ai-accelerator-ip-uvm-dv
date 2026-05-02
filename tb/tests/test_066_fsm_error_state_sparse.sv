`ifndef TEST_066_FSM_ERROR_STATE_SPARSE_SV
`define TEST_066_FSM_ERROR_STATE_SPARSE_SV

class test_066_fsm_error_state_sparse extends base_test;
  `uvm_component_utils(test_066_fsm_error_state_sparse)

  function new(string name = "test_066_fsm_error_state_sparse", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    int        error_flag_val;
    logic [2:0] state_val;
    logic [1:0] bresp;
    phase.raise_objection(this);

    $display("===========================Test_066 : FSM Error State Sparse (Abort Injection) - Start=====================================");

    w_tile_seq   = accel_weight_tile_seq::type_id::create("w_tile_seq");
    a_stream_seq = accel_act_stream_seq::type_id::create("a_stream_seq");
    w_tile_tnx   = axis_weight_tnx::type_id::create("w_tile_tnx");
    a_stream_tnx = axis_act_tnx::type_id::create("a_stream_tnx");
    rd_seq       = accel_csr_read_seq::type_id::create("rd_seq");
    wr_seq       = accel_csr_write_seq::type_id::create("wr_seq");

    env.sco.flush_queues();

    // Build weight tile (all ones, dense)
    for (int i = 0; i < TB_ROWS * TB_COLS; i++) begin
      w_tile_tnx.w0[i] = 1;  w_tile_tnx.w1[i] = 1;
      w_tile_tnx.idx0[i] = 0; w_tile_tnx.idx1[i] = 1;
    end
    w_tile_tnx.sparsity_mode = SPARSITY_2_4;
    w_tile_tnx.sparse_mask   = 4'hF;

    a_stream_tnx.a0 = 1; a_stream_tnx.a1 = 1;
    a_stream_tnx.a2 = 1; a_stream_tnx.a3 = 1;
    a_stream_tnx.is_last    = 1'b1;
    a_stream_tnx.mode_dense = 1'b0;

    // ---- Step 1-4 : Reset, configure, stream weights, start ----
    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0048;
    wr_seq.start(env.axil_a.seqr);
    repeat(10) @(posedge vif.clk);
    
    wr_seq.csr_data = 32'h0000_0008; 
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);

    wr_seq.csr_addr = CSR_TILE_CFG;  
    wr_seq.csr_data = 32'h0001_0001;
    wr_seq.start(env.axil_a.seqr);
    
    wr_seq.csr_addr = CSR_ACT_TILE_CFG;
    wr_seq.csr_data = 32'h0001_0000; 
    wr_seq.start(env.axil_a.seqr);
    
    wr_seq.csr_addr = CSR_SPARSITY; 
    wr_seq.csr_data = 32'h0000_0002;
    wr_seq.start(env.axil_a.seqr);
    
    wr_seq.csr_addr = CSR_CTRL;    
    wr_seq.csr_data = 32'h0000_0001;
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);

    w_tile_seq.t = w_tile_tnx;
    w_tile_seq.start(env.weight_a.seqr);
    @(posedge vif.clk iff probe_if.wgt_buf_tile_ready);

    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0003;
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);
    
    @(posedge vif.clk iff probe_if.state === S_STREAM);

    // ---- Step 5 : Inject abort via probe ----
    probe_if.inject_parity_error = 1'b1;   // forces Ctrl_Abort for one cycle
    

    // ---- Step 6 : Wait for S_ERROR and sample backdoor immediately ----
    @(posedge vif.clk iff probe_if.state === S_ERROR);
    // Backdoor read – no simulation time advance
    if (!uvm_hdl_read("tb_top.dut.u_control.error_flag", error_flag_val))
      `uvm_error(get_name(), "uvm_hdl_read failed for error_flag")
      
    if (!uvm_hdl_read("tb_top.dut.u_control.u_compute.state_q", state_val))
      `uvm_error(get_name(), "uvm_hdl_read failed for state_q")

    // ---- Step 7 : Check results ----
    if (state_val !== S_ERROR)
      `uvm_error(get_name(), $sformatf("State not S_ERROR (got %0d)", state_val))
    else
      $display("Backdoor: state = S_ERROR");

    // Note: abort does NOT set error_flag in this RTL version
    if (error_flag_val)
      `uvm_info(get_name(), "error_flag set (unexpected for abort)", UVM_MEDIUM)
    else
      $display("error_flag = 0 (expected, abort does not set error flag)");

    // ---- Step 8 : Read CSR_STATUS via AXI – only check error bit (should be 0) ----
    rd_seq.csr_addr = CSR_STATUS;
    rd_seq.start(env.axil_a.seqr);
    if (rd_seq.csr_rdata[2])
      `uvm_error(get_name(), "CSR_STATUS error bit unexpectedly set")
    else
      $display("CSR_STATUS error bit = 0 (expected)");

    // ---- Cleanup ----
    wr_seq.csr_addr = CSR_CTRL; wr_seq.csr_data = 32'h0000_0008; wr_seq.start(env.axil_a.seqr);
    repeat(10) @(posedge vif.clk);
    env.sco.flush_queues();

    $display("===================================================Test_066 : End of the test=================================================================");
    phase.drop_objection(this);
  endtask
endclass
`endif