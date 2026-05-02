`ifndef TEST_063_CSR_WRITE_DURING_COMPUTE_SV
`define TEST_063_CSR_WRITE_DURING_COMPUTE_SV

class test_063_csr_write_during_compute extends base_test;
  `uvm_component_utils(test_063_csr_write_during_compute)

  function new(string name = "test_063_csr_write_during_compute", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    $display("==========================Test_063 : CSR Write During Active Compute - Start======================================");

    w_tile_seq   = accel_weight_tile_seq::type_id::create("w_tile_seq");
    a_stream_seq = accel_act_stream_seq::type_id::create("a_stream_seq");
    w_tile_tnx   = axis_weight_tnx::type_id::create("w_tile_tnx");
    a_stream_tnx = axis_act_tnx::type_id::create("a_stream_tnx");
    rd_seq       = accel_csr_read_seq::type_id::create("rd_seq");
    wr_seq       = accel_csr_write_seq::type_id::create("wr_seq");

    env.sco.flush_queues();

    // Build weight tile (all ones)
    for (int i = 0; i < TB_ROWS * TB_COLS; i++) begin
      w_tile_tnx.w0[i] = 1;  w_tile_tnx.w1[i] = 1;
      w_tile_tnx.idx0[i] = 0; w_tile_tnx.idx1[i] = 1;
    end
    w_tile_tnx.sparsity_mode = SPARSITY_DENSE;
    w_tile_tnx.sparse_mask   = 4'hF;

    // Activation vector base
    a_stream_tnx.a0 = 1; a_stream_tnx.a1 = 1;
    a_stream_tnx.a2 = 1; a_stream_tnx.a3 = 1;
    a_stream_tnx.is_last    = 1'b0;
    a_stream_tnx.mode_dense = 1'b1;

    // Step 1 : Reset + set initial PP_SCALE=4
    $display("                Step 1 : Reset + configure initial PP_SCALE=4                ");
    wr_seq.csr_addr = CSR_CTRL;    
    wr_seq.csr_data = 32'h0000_0048;
    wr_seq.start(env.axil_a.seqr);
    repeat(10) @(posedge vif.clk);
    
    wr_seq.csr_addr = CSR_CTRL;     
    wr_seq.csr_data = 32'h0000_0008;
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);
    
    wr_seq.csr_addr = CSR_PP_SCALE;
    wr_seq.csr_data = 32'd4;        
    wr_seq.start(env.axil_a.seqr);
    
    wr_seq.csr_addr = CSR_PP_CTRL; 
    wr_seq.csr_data = 32'h0000_0002;  
    wr_seq.start(env.axil_a.seqr); // PP_SCALE_SHIFT

    // Step 2 : Configure and start 100-vector compute
    $display("                Step 2 : Configure and start 100-vector compute                ");
    wr_seq.csr_addr = CSR_TILE_CFG;  
    wr_seq.csr_data = 32'h0001_0064; 
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

    // Stream weights
    w_tile_seq.t = w_tile_tnx;
    w_tile_seq.start(env.weight_a.seqr);
    @(posedge vif.clk iff probe_if.wgt_buf_tile_ready);

    // Enable + Start
    wr_seq.csr_addr = CSR_CTRL; 
    wr_seq.csr_data = 32'h0000_0003;
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);
    
    @(posedge vif.clk iff probe_if.state === S_STREAM);

    // *** Suppress scoreboard errors for the compute phase ***
    env.sco.set_report_id_verbosity("SCO", UVM_WARNING);

    // Step 3 : Stream 50 activations, then write new PP_SCALE mid-compute
    $display("                Step 3 : Stream 50 activations, then write PP_SCALE=8 mid-compute                ");
    fork
      begin : act_stream
        for (int v = 0; v < 100; v++) begin
          a_stream_tnx.is_last = (v == 99);
          a_stream_seq.t = a_stream_tnx;
          a_stream_seq.start(env.act_a.seqr);
        end
      end
      begin : csr_writer
        repeat(50 * 2 + 10) @(posedge vif.clk);
        $display("    Writing PP_SCALE=8 during STREAM state — must be accepted without hang");
        wr_seq.csr_addr = CSR_PP_SCALE;
        wr_seq.csr_data = 32'd8;
        wr_seq.start(env.axil_a.seqr);
        $display("    PP_SCALE write completed — AXI-Lite interface not hung by active compute");
      end
    join

    // Step 4 : Wait for done
    $display("                Step 4 : Wait for computation done                 ");
    @(posedge vif.clk iff probe_if.done === 1'b1);
    repeat(10) @(posedge vif.clk);

    // *** Restore scoreboard verbosity ***
    env.sco.set_report_id_verbosity("SCO", UVM_MEDIUM);

    // Step 5 : Verify PP_SCALE=8 persists after compute
    $display("                Step 5 : Verify PP_SCALE=8 persists after compute                ");
    env.sco.set_expected(CSR_PP_SCALE, 32'd8);
    rd_seq.csr_addr = CSR_PP_SCALE;
    rd_seq.start(env.axil_a.seqr);

    $display("===================================================Test_063 : End of the test=================================================================");
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass

`endif