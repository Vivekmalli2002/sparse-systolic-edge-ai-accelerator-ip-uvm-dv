`ifndef TEST_060_SOFT_RESET_FROM_STREAM_SV
`define TEST_060_SOFT_RESET_FROM_STREAM_SV

class test_060_soft_reset_from_stream extends base_test;
  `uvm_component_utils(test_060_soft_reset_from_stream)

  function new(string name = "test_060_soft_reset_from_stream", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    $display("=============================Test_060 : Soft Reset from STREAM State - Start========================================");

    w_tile_seq   = accel_weight_tile_seq::type_id::create("w_tile_seq");
    a_stream_seq = accel_act_stream_seq::type_id::create("a_stream_seq");
    w_tile_tnx   = axis_weight_tnx::type_id::create("w_tile_tnx");
    a_stream_tnx = axis_act_tnx::type_id::create("a_stream_tnx");
    rd_seq       = accel_csr_read_seq::type_id::create("rd_seq");

    env.sco.flush_queues();

    // Build weight tile (all ones)
    for (int i = 0; i < TB_ROWS * TB_COLS; i++) begin
      w_tile_tnx.w0[i] = 1;  w_tile_tnx.w1[i] = 1;
      w_tile_tnx.idx0[i] = 0; w_tile_tnx.idx1[i] = 1;
    end
    w_tile_tnx.sparsity_mode = SPARSITY_DENSE;
    w_tile_tnx.sparse_mask   = 4'hF;

    // Activation vector (a=1)
    a_stream_tnx.a0 = 1; a_stream_tnx.a1 = 1;
    a_stream_tnx.a2 = 1; a_stream_tnx.a3 = 1;
    a_stream_tnx.is_last    = 1'b0;
    a_stream_tnx.mode_dense = 1'b1;

    // Run 100 vectors, soft reset at vector 50
    run_compute_test_with_mid_reset(w_tile_tnx, a_stream_tnx,
                                    32'h0000_0001, 100, 50, "Test_060");

    // Wait for DUT to fully recover from soft reset
    drain_after_reset();
    env.sco.flush_queues();

    // Verify FSM = IDLE via scoreboard.
    // NOTE: done bit remains '1' after soft reset (hardware behaviour) – CSR_STATUS = 0x2.
    $display("                Step : Verify CSR_STATUS = 0x2 (FSM = S_IDLE, done=1)                ");
    env.sco.set_expected(CSR_STATUS, 32'h0000_0002);
    rd_seq.csr_addr = CSR_STATUS;
    rd_seq.start(env.axil_a.seqr);

    $display("===================================================Test_060 : End of the test=================================================================");
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
  
endclass

`endif