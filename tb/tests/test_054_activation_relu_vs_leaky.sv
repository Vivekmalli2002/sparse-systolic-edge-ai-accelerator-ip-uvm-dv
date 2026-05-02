`ifndef TEST_054_ACTIVATION_RELU_VS_LEAKY_SV
`define TEST_054_ACTIVATION_RELU_VS_LEAKY_SV

class test_054_activation_relu_vs_leaky extends base_test;
  `uvm_component_utils(test_054_activation_relu_vs_leaky)

  function new(string name = "test_054_activation_relu_vs_leaky", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // Helper task to run one activation‑function pass
  task run_activation_pass(bit [2:0] act_fn, int expected_output);
    // Soft reset
    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0048;
    wr_seq.start(env.axil_a.seqr);
    repeat(10) @(posedge vif.clk);
    
    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0008;
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);

    // Set activation function via CSR_ACT_CFG
    wr_seq.csr_addr = CSR_ACT_CFG; 
    wr_seq.csr_data = {29'b0, act_fn}; 
    wr_seq.start(env.axil_a.seqr);

    // PP: no bias, no scale/shift, no saturation
    wr_seq.csr_addr = CSR_PP_CTRL; 
    wr_seq.csr_data = 32'h0; 
    wr_seq.start(env.axil_a.seqr);
    
    wr_seq.csr_addr = CSR_PP_SCALE; 
    wr_seq.csr_data = 32'd1;
    wr_seq.start(env.axil_a.seqr);
    
    wr_seq.csr_addr = CSR_PP_SHIFT;
    wr_seq.csr_data = 0;     
    wr_seq.start(env.axil_a.seqr);
    
    wr_seq.csr_addr = CSR_PP_SAT_MAX;
    wr_seq.csr_data = 32'h7FFF_FFFF;
    wr_seq.start(env.axil_a.seqr);
    
    wr_seq.csr_addr = CSR_PP_SAT_MIN;
    wr_seq.csr_data = 32'h8000_0000; 
    wr_seq.start(env.axil_a.seqr);

    // Configure compute
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

    // Stream weights (all -1)
    w_tile_seq.t = w_tile_tnx;
    w_tile_seq.start(env.weight_a.seqr);
    @(posedge vif.clk iff probe_if.wgt_buf_tile_ready);

    // Enable + Start
    wr_seq.csr_addr = CSR_CTRL; 
    wr_seq.csr_data = 32'h0000_0003; 
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);
    @(posedge vif.clk iff probe_if.state === S_STREAM);

    // Stream activation
    a_stream_seq.t = a_stream_tnx;
    a_stream_seq.start(env.act_a.seqr);

    // Wait for done
    @(posedge vif.clk iff probe_if.done === 1'b1);
    repeat(10) @(posedge vif.clk);

    $display("    Activation pass fn=%0d complete (expected output=%0d)", act_fn, expected_output);
    // Scoreboard automatically checks the result
  endtask

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    $display("===================================================Test_054 : Activation Function ReLU vs Leaky ReLU - Start=================================================================");

    w_tile_seq   = accel_weight_tile_seq::type_id::create("w_tile_seq");
    a_stream_seq = accel_act_stream_seq::type_id::create("a_stream_seq");
    w_tile_tnx   = axis_weight_tnx::type_id::create("w_tile_tnx");
    a_stream_tnx = axis_act_tnx::type_id::create("a_stream_tnx");
    wr_seq       = accel_csr_write_seq::type_id::create("wr_seq");

    env.sco.flush_queues();

    // Build weight tile (all -1) to generate negative psum
    for (int i = 0; i < TB_ROWS * TB_COLS; i++) begin
      w_tile_tnx.w0[i] = -1; w_tile_tnx.w1[i] = -1;
      w_tile_tnx.idx0[i] = 0; w_tile_tnx.idx1[i] = 1;
    end
    w_tile_tnx.sparsity_mode = SPARSITY_DENSE;
    w_tile_tnx.sparse_mask   = 4'hF;

    // Activation (all +1)
    a_stream_tnx.a0 = 1; a_stream_tnx.a1 = 1;
    a_stream_tnx.a2 = 1; a_stream_tnx.a3 = 1;
    a_stream_tnx.is_last    = 1'b1;
    a_stream_tnx.mode_dense = 1'b1;

    // ReLU pass — expect 0 (negative → 0)
    $display("                ReLU pass: psum=-32 → expected output=0                ");
    run_activation_pass(3'b001, 0);

    // Leaky ReLU pass — expect -4 (psum>>>3)
    $display("                Leaky ReLU pass: psum=-32 → expected output=-4                ");
    run_activation_pass(3'b011, -4);

    $display("===================================================Test_054 : End of the test=================================================================");
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass

`endif