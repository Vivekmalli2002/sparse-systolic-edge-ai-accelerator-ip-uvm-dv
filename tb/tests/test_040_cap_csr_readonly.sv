`ifndef TEST_040_CAP_CSR_READONLY_SV
`define TEST_040_CAP_CSR_READONLY_SV

class test_040_cap_csr_readonly extends base_test;
  `uvm_component_utils(test_040_cap_csr_readonly)

  function new(string name = "test_040_cap_csr_readonly", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    $display("===============================Test_040 : Capability CSR Read-Only Sanity - Start===========================================");

    rd_seq = accel_csr_read_seq::type_id::create("rd_seq");
    wr_seq = accel_csr_write_seq::type_id::create("wr_seq");
    env.sco.flush_queues();

    // ---- Step 1 : Read CSR_CAP0 ----
    $display("                Step 1 : Read CSR_CAP0                ");
    env.sco.set_expected(CSR_CAP0, 32'h02031010);   // ROWS=16, COLS=16, PE_STAGES=2
    rd_seq.csr_addr = CSR_CAP0;
    rd_seq.start(env.axil_a.seqr);

    // ---- Step 2 : Read CSR_CAP1 ----
    $display("                Step 2 : Read CSR_CAP1                ");
    env.sco.set_expected(CSR_CAP1, 32'h02001010);   // expected value from your log
    rd_seq.csr_addr = CSR_CAP1;
    rd_seq.start(env.axil_a.seqr);

    // ---- Step 3 : Read CSR_CAP2 ----
    $display("                Step 3 : Read CSR_CAP2                ");
    env.sco.set_expected(CSR_CAP2, 32'h000000FF);   // all feature bits set
    rd_seq.csr_addr = CSR_CAP2;
    rd_seq.start(env.axil_a.seqr);

    // ---- Step 4 : Verify CSR_VERSION ----
    $display("                Step 4 : Verify CSR_VERSION = 0x12040000                ");
    env.sco.set_expected(CSR_VERSION, 32'h12040000);
    rd_seq.csr_addr = CSR_VERSION;
    rd_seq.start(env.axil_a.seqr);

    // ---- Step 5 : Attempt write to read-only CSR_CAP0 ----
    $display("                Step 5 : Write to CSR_CAP0 (must be read-only)                ");
    wr_seq.csr_addr = CSR_CAP0;
    wr_seq.csr_data = 32'hDEAD_BEEF;
    wr_seq.start(env.axil_a.seqr);
    // After write, set the expected to the ORIGINAL read-only value
    env.sco.set_expected(CSR_CAP0, 32'h02031010);
    rd_seq.csr_addr = CSR_CAP0;
    rd_seq.start(env.axil_a.seqr);

    // ---- Step 6 : Attempt write to read-only CSR_VERSION ----
    $display("                Step 6 : Write to CSR_VERSION (must be read-only)                ");
    wr_seq.csr_addr = CSR_VERSION;
    wr_seq.csr_data = 32'hFFFF_FFFF;
    wr_seq.start(env.axil_a.seqr);
    env.sco.set_expected(CSR_VERSION, 32'h12040000);
    rd_seq.csr_addr = CSR_VERSION;
    rd_seq.start(env.axil_a.seqr);

    $display("===================================================Test_040 : End of the test=================================================================");
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
  
endclass

`endif