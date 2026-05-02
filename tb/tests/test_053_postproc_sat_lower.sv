`ifndef TEST_053_POSTPROC_SAT_LOWER_SV
`define TEST_053_POSTPROC_SAT_LOWER_SV

class test_053_postproc_sat_lower extends base_test;
  `uvm_component_utils(test_053_postproc_sat_lower)

  function new(string name = "test_053_postproc_sat_lower", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    $display("======================Test_053 : Saturation Lower Clamp (via PP_BIAS_ADD + bias=0) - Start==========================");

    w_tile_seq   = accel_weight_tile_seq::type_id::create("w_tile_seq");
    a_stream_seq = accel_act_stream_seq::type_id::create("a_stream_seq");
    w_tile_tnx   = axis_weight_tnx::type_id::create("w_tile_tnx");
    a_stream_tnx = axis_act_tnx::type_id::create("a_stream_tnx");
    wr_seq       = accel_csr_write_seq::type_id::create("wr_seq");

    env.sco.flush_queues();

    // Build weight tile (min negative = -128)
    for (int i = 0; i < TB_ROWS * TB_COLS; i++) begin
      w_tile_tnx.w0[i] = -128; w_tile_tnx.w1[i] = -128;
      w_tile_tnx.idx0[i] = 0; w_tile_tnx.idx1[i] = 1;
    end
    w_tile_tnx.sparsity_mode = SPARSITY_DENSE;
    w_tile_tnx.sparse_mask   = 4'hF;

    // Activation (max positive)
    a_stream_tnx.a0 = 127; a_stream_tnx.a1 = 127;
    a_stream_tnx.a2 = 127; a_stream_tnx.a3 = 127;
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

    // Step 2 : Configure PP — PP_BIAS_ADD, bias=0, scale=1, shift=0, sat_en=1, SAT_MIN=-50
    $display("                Step 2 : Configure PP — PP_BIAS_ADD, bias=0, scale=1, sat_en=1, SAT_MIN=-50                ");
    wr_seq.csr_addr = CSR_PP_CTRL;   
    wr_seq.csr_data = 32'h0000_0201;  // PP_BIAS_ADD + sat_en
    wr_seq.start(env.axil_a.seqr);
    
    wr_seq.csr_addr = CSR_PP_SCALE; 
    wr_seq.csr_data = 32'd1;
    wr_seq.start(env.axil_a.seqr);
    
    wr_seq.csr_addr = CSR_PP_SHIFT;  
    wr_seq.csr_data = 0;
    wr_seq.start(env.axil_a.seqr);
    
    wr_seq.csr_addr = CSR_PP_SAT_MAX;
    wr_seq.csr_data = 32'h7FFF_FFFF;  // large max
    wr_seq.start(env.axil_a.seqr);
    
    wr_seq.csr_addr = CSR_PP_SAT_MIN; 
    wr_seq.csr_data = 32'hFFFF_FFCE;  // -50 in 2's complement
    wr_seq.start(env.axil_a.seqr);

    // Load zero bias for all 16 columns
    wr_seq.csr_addr = CSR_PP_BIAS_ADDR; wr_seq.csr_data = 32'h0;
    wr_seq.start(env.axil_a.seqr);
    for (int c = 0; c < 16; c++) begin
      wr_seq.csr_addr = CSR_PP_BIAS_DATA;
      wr_seq.csr_data = 32'h0;
      wr_seq.start(env.axil_a.seqr);
    end

    // Step 3 : Configure compute — negative weights, 1 vector, dense
    $display("                Step 3 : Configure compute — w=-128, a=127, 1 vector                ");
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
    $display("                Step 4 : Stream min weights (-128)                ");
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
    $display("                Step 6 : Stream 1 activation vector (a=127)                ");
    a_stream_seq.t = a_stream_tnx;
    a_stream_seq.start(env.act_a.seqr);

    // Wait for done – scoreboard checks result (expected -50 if saturation works, else raw negative psum)
    $display("                Step 7 : Wait for computation done — scoreboard checks saturation (min=-50)                ");
    @(posedge vif.clk iff probe_if.done === 1'b1);
    repeat(10) @(posedge vif.clk);

    $display("===================================================Test_053 : End of the test=================================================================");
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass

`endif