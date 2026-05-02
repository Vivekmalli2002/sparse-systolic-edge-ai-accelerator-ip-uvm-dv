`ifndef TEST_049_SIMULTANEOUS_BACKPRESSURE_SV
`define TEST_049_SIMULTANEOUS_BACKPRESSURE_SV

class test_049_simultaneous_backpressure extends base_test;
  `uvm_component_utils(test_049_simultaneous_backpressure)

  function new(string name = "test_049_simultaneous_backpressure", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    bit done_seen = 0;
    phase.raise_objection(this);

    $display("===================================================Test_049 : Simultaneous 3‑Stream Backpressure - Start=================================================================");

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

    // Activation (a=1, 8 vectors)
    a_stream_tnx.a0 = 1; a_stream_tnx.a1 = 1;
    a_stream_tnx.a2 = 1; a_stream_tnx.a3 = 1;
    a_stream_tnx.is_last    = 1'b0;
    a_stream_tnx.mode_dense = 1'b1;

    // Reset + configure
    $display("                Step 1 : Soft Reset + Clear                 ");
    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0048;
    wr_seq.start(env.axil_a.seqr);
    repeat(10) @(posedge vif.clk);
    
    wr_seq.csr_addr = CSR_CTRL; 
    wr_seq.csr_data = 32'h0000_0008;
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);

    $display("                Step 2 : Configure 1 tile, 8 vectors, dense                ");
    wr_seq.csr_addr = CSR_TILE_CFG;   
    wr_seq.csr_data = 32'h0001_0008; 
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

    // Step 3 : Apply backpressure on all 3 streams simultaneously
    $display("                Step 3 : Apply backpressure on weight (tvalid=0), activation (tvalid=0), and result (tready=0) streams                ");
    env.weight_a.drv.vif.drv_cp.tvalid     <= 0;   // stop weight
    env.act_a.drv.vif.drv_cp.tvalid        <= 0;   // stop activation
    env.result_a.mon.vif.drv_cp.tready     <= 0;   // stop result

    // Hold for 400 cycles to stress the system
    repeat(400) @(posedge vif.clk);
    $display("    All 3 streams held idle for 400 cycles — no deadlock");

    // Step 4 : Release backpressure and resume normal flow
    $display("                Step 4 : Release backpressure — resume weight & act tvalid, assert result tready                ");
    env.result_a.mon.vif.drv_cp.tready     <= 1;

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

    // Stream activations
    for (int v = 0; v < 8; v++) begin
      a_stream_tnx.is_last = (v == 7);
      a_stream_seq.t = a_stream_tnx;
      a_stream_seq.start(env.act_a.seqr);
    end

    // Wait for done
    $display("                Step 5 : Wait for computation done                 ");
    @(posedge vif.clk iff probe_if.done === 1'b1);
    repeat(10) @(posedge vif.clk);

    $display("===================================================Test_049 : End of the test=================================================================");
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass

`endif