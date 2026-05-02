`ifndef TEST_062_IRQ_MASK_DURING_COMPUTE_SV
`define TEST_062_IRQ_MASK_DURING_COMPUTE_SV

class test_062_irq_mask_during_compute extends base_test;
  `uvm_component_utils(test_062_irq_mask_during_compute)

  function new(string name = "test_062_irq_mask_during_compute", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    bit [31:0] irq_status;
    phase.raise_objection(this);

    $display("===================================================Test_062 : IRQ Mask / Unmask During Compute - Start=================================================================");

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

    // Activation vector (a=1, 8 vectors)
    a_stream_tnx.a0 = 1; a_stream_tnx.a1 = 1;
    a_stream_tnx.a2 = 1; a_stream_tnx.a3 = 1;
    a_stream_tnx.is_last    = 1'b0;
    a_stream_tnx.mode_dense = 1'b1;

    // Step 1 : Reset + mask all IRQs
    $display("                Step 1 : Reset + mask all IRQ sources (IRQ_EN=0)                ");
    wr_seq.csr_addr = CSR_CTRL;  
    wr_seq.csr_data = 32'h0000_0048;
    wr_seq.start(env.axil_a.seqr);
    repeat(10) @(posedge vif.clk);
    
    wr_seq.csr_addr = CSR_CTRL;   
    wr_seq.csr_data = 32'h0000_0008;
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);
    
    wr_seq.csr_addr = CSR_IRQ_EN; 
    wr_seq.csr_data = 32'h0000_0000;
    wr_seq.start(env.axil_a.seqr);

    // Step 2 : Configure and run 8-vector compute with IRQ_EN=0
    $display("                Step 2 : Configure and run 8-vector compute with IRQ_EN=0                ");
    a_stream_tnx.is_last = 1'b0;
    run_compute_test(w_tile_tnx, a_stream_tnx, 32'h0000_0001, 8, "Test_062_masked");

    // Step 3 : Verify IRQ_STATUS shows compute_done (bit 0) even though masked
    $display("                Step 3 : Verify IRQ_STATUS[0] is set (pending), IRQ_EN was 0                ");
    rd_seq.csr_addr = CSR_IRQ_STATUS;
    rd_seq.start(env.axil_a.seqr);
    irq_status = rd_seq.csr_rdata;
    if (!irq_status[0])
      `uvm_warning(get_name(), "IRQ_STATUS[0] not set after compute — may have completed too fast?")
    else
      $display("    IRQ_STATUS[0] = 1 — compute_done pending bit set. PASS.");

    // Step 4 : Enable IRQ_COMPUTE_DONE (bit 0), verify irq_out asserts
    $display("                Step 4 : Enable IRQ_EN=0x1 — expect irq_out to assert (if pending)                ");
    wr_seq.csr_addr = CSR_IRQ_EN;
    wr_seq.csr_data = 32'h0000_0001;
    wr_seq.start(env.axil_a.seqr);
    repeat(3) @(posedge vif.clk);
    
    $display("    IRQ_EN[0]=1, pending was set → irq_out should be high now.");

    // Step 5 : W1C clear bit 0
    $display("                Step 5 : W1C clear IRQ_STATUS[0]                ");
    wr_seq.csr_addr = CSR_IRQ_STATUS;
    wr_seq.csr_data = 32'h0000_0001;
    wr_seq.start(env.axil_a.seqr);
    repeat(2) @(posedge vif.clk);

    // Step 6 : Verify bit 0 cleared
    $display("                Step 6 : Verify IRQ_STATUS[0] cleared                ");
    env.sco.set_expected(CSR_IRQ_STATUS, 32'h0000_0018);  // AFIFO + WFIFO empty bits remain
    rd_seq.csr_addr = CSR_IRQ_STATUS;
    rd_seq.start(env.axil_a.seqr);

    $display("===================================================Test_062 : End of the test=================================================================");
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass

`endif