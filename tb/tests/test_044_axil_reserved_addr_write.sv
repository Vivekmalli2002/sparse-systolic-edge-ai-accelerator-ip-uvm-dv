`ifndef TEST_044_AXIL_RESERVED_ADDR_WRITE_SV
`define TEST_044_AXIL_RESERVED_ADDR_WRITE_SV

class test_044_axil_reserved_addr_write extends base_test;
  `uvm_component_utils(test_044_axil_reserved_addr_write)

  function new(string name = "test_044_axil_reserved_addr_write", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    bit [31:0] status_before, status_after;
    bit [31:0] irq_before, irq_after;
    phase.raise_objection(this);

    $display("===========================Test_044 : Reserved CSR Address Write - Start============================================");

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

    // ---- Step 2 : Sample baseline STATUS and IRQ_STATUS ----
    $display("                Step 2 : Sample baseline STATUS and IRQ_STATUS                ");
    // Read STATUS (no expected value needed – we only want the raw value)
    env.sco.set_expected(CSR_STATUS, 32'h0000_0000);
    rd_seq.csr_addr = CSR_STATUS;
    rd_seq.start(env.axil_a.seqr);
    status_before = rd_seq.csr_rdata;

    env.sco.set_expected(CSR_IRQ_STATUS, 32'h0000_0018);   // reset value
    rd_seq.csr_addr = CSR_IRQ_STATUS;
    rd_seq.start(env.axil_a.seqr);
    irq_before = rd_seq.csr_rdata;

    // ---- Step 3 : Write to 8 reserved addresses ----
    $display("                Step 3 : Write to 8 reserved CSR addresses (0x100-0x1F0)                ");
    begin
      automatic bit [11:0] reserved[8] = '{12'h100, 12'h110, 12'h120, 12'h140,
                                           12'h160, 12'h180, 12'h1A0, 12'h1F0};
      foreach (reserved[i]) begin
        wr_seq.csr_addr = reserved[i];
        wr_seq.csr_data = 32'hDEAD_BEEF;
        wr_seq.start(env.axil_a.seqr);
        $display($sformatf("    Wrote 0xDEADBEEF to reserved addr 0x%03X", reserved[i]));
      end
    end

    // ---- Step 4 : Verify STATUS and IRQ unchanged ----
    $display("                Step 4 : Verify FSM state and IRQ unchanged                ");
    rd_seq.csr_addr = CSR_STATUS;
    rd_seq.start(env.axil_a.seqr);
    status_after = rd_seq.csr_rdata;

    rd_seq.csr_addr = CSR_IRQ_STATUS;
    rd_seq.start(env.axil_a.seqr);
    irq_after = rd_seq.csr_rdata;

    if (status_after !== status_before)
      `uvm_error(get_name(), $sformatf("STATUS changed! before=0x%08X after=0x%08X", status_before, status_after))
    else
      $display("    STATUS unchanged – no spurious FSM transition. PASS.");

    if (irq_after !== irq_before)
      `uvm_error(get_name(), $sformatf("IRQ_STATUS changed! before=0x%08X after=0x%08X", irq_before, irq_after))
    else
      $display("    IRQ_STATUS unchanged – no spurious interrupt. PASS.");

    // ---- Step 5 : Confirm next valid write still works ----
    $display("                Step 5 : Next valid write to CSR_SPARSITY works correctly                ");
    wr_seq.csr_addr = CSR_SPARSITY;
    wr_seq.csr_data = 32'h3;           // 4:8 sparse
    wr_seq.start(env.axil_a.seqr);

    env.sco.set_expected(CSR_SPARSITY, 32'h3);
    rd_seq.csr_addr = CSR_SPARSITY;
    rd_seq.start(env.axil_a.seqr);

    $display("===================================================Test_044 : End of the test=================================================================");
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass

`endif