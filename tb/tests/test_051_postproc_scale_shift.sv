`ifndef TEST_051_POSTPROC_SCALE_SHIFT_SV
`define TEST_051_POSTPROC_SCALE_SHIFT_SV

class test_051_postproc_scale_shift extends base_test;
  `uvm_component_utils(test_051_postproc_scale_shift)

  function new(string name = "test_051_postproc_scale_shift", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    $display("========================Test_051 : Post-Proc Scale+Shift Quantization - Start==================================");

    w_tile_seq   = accel_weight_tile_seq::type_id::create("w_tile_seq");
    a_stream_seq = accel_act_stream_seq::type_id::create("a_stream_seq");
    w_tile_tnx   = axis_weight_tnx::type_id::create("w_tile_tnx");
    a_stream_tnx = axis_act_tnx::type_id::create("a_stream_tnx");
    wr_seq       = accel_csr_write_seq::type_id::create("wr_seq");

    env.sco.flush_queues();

    // Build weight tile (all ones)
    for (int i = 0; i < TB_ROWS * TB_COLS; i++) begin
      w_tile_tnx.w0[i] = 1;  w_tile_tnx.w1[i] = 1;
      w_tile_tnx.idx0[i] = 0; w_tile_tnx.idx1[i] = 1;
    end
    w_tile_tnx.sparsity_mode = SPARSITY_DENSE;
    w_tile_tnx.sparse_mask   = 4'hF;

    // Activation vector (all ones, 1 vector)
    a_stream_tnx.a0 = 1; a_stream_tnx.a1 = 1;
    a_stream_tnx.a2 = 1; a_stream_tnx.a3 = 1;
    a_stream_tnx.is_last    = 1'b1;
    a_stream_tnx.mode_dense = 1'b1;

    // Step 1 : Soft Reset + Clear
    $display("                Step 1 : Soft Reset + Clear                 ");
    wr_seq.csr_addr = CSR_CTRL; 
    wr_seq.csr_data = 32'h0000_0048;
    wr_seq.start(env.axil_a.seqr);
    repeat(10) @(posedge vif.clk);
    
    wr_seq.csr_addr = CSR_CTRL; 
    wr_seq.csr_data = 32'h0000_0008;
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);

    // Step 2 : Configure PP — PP_SCALE_SHIFT, scale=2, shift=0
    $display("                Step 2 : Configure PP — PP_SCALE_SHIFT, scale=2, shift=0                ");
    wr_seq.csr_addr = CSR_PP_CTRL; 
    wr_seq.csr_data = 32'h0000_0002;  // PP_SCALE_SHIFT
    wr_seq.start(env.axil_a.seqr);
    
    wr_seq.csr_addr = CSR_PP_SCALE; 
    wr_seq.csr_data = 32'd2;
    wr_seq.start(env.axil_a.seqr);
    
    wr_seq.csr_addr = CSR_PP_SHIFT; 
    wr_seq.csr_data = 32'd0;
    wr_seq.start(env.axil_a.seqr);
    
    wr_seq.csr_addr = CSR_PP_SAT_MAX;
    wr_seq.csr_data = 32'h7FFF_FFFF;
    wr_seq.start(env.axil_a.seqr);
    
    wr_seq.csr_addr = CSR_PP_SAT_MIN;
    wr_seq.csr_data = 32'h8000_0000;
    wr_seq.start(env.axil_a.seqr);

    // Step 3 : Configure compute — 1 tile, 1 vector, dense
    $display("                Step 3 : Configure compute — all‑ones weights, 1 vector, dense                ");
    wr_seq.csr_addr = CSR_TILE_CFG;    
    wr_seq.csr_data = 32'h0001_0001; 
    wr_seq.start(env.axil_a.seqr);
    
    wr_seq.csr_addr = CSR_ACT_TILE_CFG;
    wr_seq.csr_data = 32'h0001_0000;
    wr_seq.start(env.axil_a.seqr);
    
    wr_seq.csr_addr = CSR_SPARSITY;  
    wr_seq.csr_data = 32'h0000_0001; 
    wr_seq.start(env.axil_a.seqr);
    
    wr_seq.csr_addr = CSR_CTRL;      
    wr_seq.csr_data = 32'h0000_0001;
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);

    // Step 4 : Stream weights
    $display("                Step 4 : Stream all‑ones weights                ");
    w_tile_seq.t = w_tile_tnx;
    w_tile_seq.start(env.weight_a.seqr);
    @(posedge vif.clk iff probe_if.wgt_buf_tile_ready);

    // Step 5 : Enable + Start
    $display("                Step 5 : Enable + Start                 ");
    wr_seq.csr_addr = CSR_CTRL; 
    wr_seq.csr_data = 32'h0000_0003;
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);
    @(posedge vif.clk iff probe_if.state === S_STREAM);

    // Step 6 : Stream 1 activation
    $display("                Step 6 : Stream 1 activation vector (all a=1)                ");
    a_stream_seq.t = a_stream_tnx;
    a_stream_seq.start(env.act_a.seqr);

    // Step 7 : Wait for done (scoreboard checks everything)
    $display("                Step 7 : Wait for computation done — scoreboard verifies scale=2, shift=0 => output=128                ");
    @(posedge vif.clk iff probe_if.done === 1'b1);
    repeat(10) @(posedge vif.clk);

    $display("===================================================Test_051 : End of the test=================================================================");
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass

`endif