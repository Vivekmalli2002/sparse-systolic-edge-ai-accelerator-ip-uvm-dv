`ifndef TEST_042_AXIL_READ_DURING_WRITE_SV
`define TEST_042_AXIL_READ_DURING_WRITE_SV

class test_042_axil_read_during_write extends base_test;
  `uvm_component_utils(test_042_axil_read_during_write)

  function new(string name = "test_042_axil_read_during_write", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    $display("=============================Test_042 : AXI-Lite Read-During-Write Isolation - Start==========================================");

    wr_seq = accel_csr_write_seq::type_id::create("wr_seq");
    rd_seq = accel_csr_read_seq::type_id::create("rd_seq");
    env.sco.flush_queues();

    // ---- Step 1 : Soft Reset + Clear ----
    $display("                Step 1 : Soft Reset + Clear                ");
    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0048;
    wr_seq.start(env.axil_a.seqr);
    repeat(10) @(posedge vif.clk);

    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0008;
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);

    // ---- Step 2 : Read SPARSITY baseline ----
    $display("                Step 2 : Read CSR_SPARSITY baseline                ");
    env.sco.set_expected(CSR_SPARSITY, 32'h0000_0001);   // reset default = dense
    rd_seq.csr_addr = CSR_SPARSITY;
    rd_seq.start(env.axil_a.seqr);

    // ---- Step 3 : Write CTRL (enable) and immediately read SPARSITY ----
    $display("                Step 3 : Write CSR_CTRL=0x1 then immediately read CSR_SPARSITY                ");
    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0001;
    wr_seq.start(env.axil_a.seqr);

    // Immediately read SPARSITY – the BVALID from the write may still be pending
    env.sco.set_expected(CSR_SPARSITY, 32'h0000_0001);
    rd_seq.csr_addr = CSR_SPARSITY;
    rd_seq.start(env.axil_a.seqr);

    // ---- Step 4 : Write PP_SCALE while reading STATUS (different registers) ----
    $display("                Step 4 : Write PP_SCALE during STATUS read                ");
    wr_seq.csr_addr = CSR_PP_SCALE;
    wr_seq.csr_data = 32'h0000_ABCD;
    wr_seq.start(env.axil_a.seqr);

    // Read STATUS while the PP_SCALE write is still completing
    env.sco.set_expected(CSR_STATUS, 32'h0000_0000);   // idle after reset + enable
    rd_seq.csr_addr = CSR_STATUS;
    rd_seq.start(env.axil_a.seqr);

    // Verify PP_SCALE landed correctly
    env.sco.set_expected(CSR_PP_SCALE, 32'h0000_ABCD);
    rd_seq.csr_addr = CSR_PP_SCALE;
    rd_seq.start(env.axil_a.seqr);

    // ---- Step 5 : Disable ----
    $display("                Step 5 : Disable CTRL                ");
    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0000;
    wr_seq.start(env.axil_a.seqr);

    $display("===================================================Test_042 : End of the test=================================================================");
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
  
endclass
`endif