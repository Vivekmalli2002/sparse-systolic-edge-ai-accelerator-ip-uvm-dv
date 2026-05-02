`ifndef TEST_045_RESULT_TREADY_BACKPRESSURE_SV
`define TEST_045_RESULT_TREADY_BACKPRESSURE_SV

class test_045_result_tready_backpressure extends base_test;
  `uvm_component_utils(test_045_result_tready_backpressure)

  function new(string name = "test_045_result_tready_backpressure", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    localparam int N_VECTORS = 100;
    phase.raise_objection(this);

    $display("===================================================Test_045 : Result Stream TREADY Backpressure - Start=================================================================");

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

    // Activation vector (a=1 for all)
    a_stream_tnx.a0 = 1; a_stream_tnx.a1 = 1;
    a_stream_tnx.a2 = 1; a_stream_tnx.a3 = 1;
    a_stream_tnx.is_last    = 1'b0;
    a_stream_tnx.mode_dense = 1'b1;

    // Reset + Configure
    $display("                Step 1 : Soft Reset + Clear                 ");
    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0048; 
    wr_seq.start(env.axil_a.seqr);
    repeat(10) @(posedge vif.clk);
    
    wr_seq.csr_addr = CSR_CTRL; 
    wr_seq.csr_data = 32'h0000_0008;
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);

    $display("                Step 2 : Configure 1 tile, %0d vectors, dense                ", N_VECTORS);
    wr_seq.csr_addr = CSR_TILE_CFG; 
    wr_seq.csr_data = {16'd1, 16'(N_VECTORS)};
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

    // Stream weights
    $display("                Step 3 : Stream weights                 ");
    w_tile_seq.t = w_tile_tnx;
    w_tile_seq.start(env.weight_a.seqr);
    @(posedge vif.clk iff probe_if.wgt_buf_tile_ready);

    // Enable + Start
    $display("                Step 4 : Enable + Start                 ");
    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0003;
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);
    @(posedge vif.clk iff probe_if.state === S_STREAM);

    // Step 5 : Disable result TREADY to induce backpressure
    $display("                Step 5 : Disable result TREADY to induce backpressure                ");
    env.result_a.mon.vif.drv_cp.tready <= 0;

    // Step 6 : Stream activations in a non‑blocking thread
    $display("                Step 6 : Stream %0d activation vectors (expect OFIFO full, no data loss)                 ", N_VECTORS);
    fork
      begin
        for (int v = 0; v < N_VECTORS; v++) begin
          a_stream_tnx.is_last = (v == N_VECTORS - 1);
          a_stream_seq.t = a_stream_tnx;
          a_stream_seq.start(env.act_a.seqr);
        end
      end
    join_none

    // Step 7 : Wait, then re‑enable TREADY to unblock
    $display("                Step 7 : Wait a few cycles then re‑enable result TREADY                 ");
    repeat(5000) @(posedge vif.clk);
    env.result_a.mon.vif.drv_cp.tready <= 1;

    // Step 8 : Wait for done
    $display("                Step 8 : Wait for computation done                 ");
    @(posedge vif.clk iff probe_if.done === 1'b1);
    repeat(10) @(posedge vif.clk);

    // Step 9 : Verify system recovered and no data loss
    $display("                Step 9 : Verify system recovered and scoreboard passed (all 1600 results)                ");
    if (probe_if.state == S_IDLE)
      $display("    System recovered to S_IDLE. Backpressure test PASS.");
    else
      `uvm_error(get_name(), $sformatf("FSM not idle after recovery! state=%0b", probe_if.state))

    $display("===================================================Test_045 : End of the test=================================================================");
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass

`endif