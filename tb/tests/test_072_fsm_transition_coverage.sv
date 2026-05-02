`ifndef TEST_072_FSM_TRANSITION_COVERAGE_SV
`define TEST_072_FSM_TRANSITION_COVERAGE_SV

class test_072_fsm_transition_coverage extends base_test;
  `uvm_component_utils(test_072_fsm_transition_coverage)

  function new(string name = "test_072_fsm_transition_coverage", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    $display("===================================================Test_072 : FSM Transition Arc Coverage - Start=================================================================");

    wr_seq = accel_csr_write_seq::type_id::create("wr_seq");
    rd_seq = accel_csr_read_seq::type_id::create("rd_seq");
    w_tile_seq = accel_weight_tile_seq::type_id::create("w_tile_seq");
    a_stream_seq = accel_act_stream_seq::type_id::create("a_stream_seq");
    env.sco.flush_queues();

    // Build weight tile (all ones)
    w_tile_tnx = axis_weight_tnx::type_id::create("w_tile");
    for (int i = 0; i < TB_ROWS * TB_COLS; i++) begin
      w_tile_tnx.w0[i] = 1; w_tile_tnx.w1[i] = 1;
      w_tile_tnx.idx0[i] = 0; w_tile_tnx.idx1[i] = 1;
    end
    w_tile_tnx.sparsity_mode = SPARSITY_DENSE;
    w_tile_tnx.sparse_mask   = 4'hF;

    // Activation vector (a=1, 4 vectors)
    a_stream_tnx = axis_act_tnx::type_id::create("a_vec");
    a_stream_tnx.a0 = 1; a_stream_tnx.a1 = 1;
    a_stream_tnx.a2 = 1; a_stream_tnx.a3 = 1;
    a_stream_tnx.is_last    = 1'b1;
    a_stream_tnx.mode_dense = 1'b1;

    // ---- Arcs 1-4 : Normal path IDLE→LOAD→STREAM→DRAIN→IDLE ----
    $display("                Arcs 1-4 : Normal 4-vector compute                ");
    run_compute_test(w_tile_tnx, a_stream_tnx, 32'h0000_0001, 4, "T072_arcs1-4");
    // Verify FSM = IDLE (done flag set)
    env.sco.set_expected(CSR_STATUS, 32'h0000_0002);
    rd_seq.csr_addr = CSR_STATUS;
    rd_seq.start(env.axil_a.seqr);

    // Arc 5 (soft reset from STREAM) is covered in T060.
    // Arc 6 (IDLE→LOAD for new compute) is covered in every functional test.

    $display("===================================================Test_072 : End of the test=================================================================");
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass

`endif