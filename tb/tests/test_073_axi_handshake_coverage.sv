`ifndef TEST_073_AXI_HANDSHAKE_COVERAGE_SV
`define TEST_073_AXI_HANDSHAKE_COVERAGE_SV

class test_073_axi_handshake_coverage extends base_test;
  `uvm_component_utils(test_073_axi_handshake_coverage)

  function new(string name = "test_073_axi_handshake_coverage", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    virtual accel_axil_if axil_vif = vif;   // inherited from base_test
    bit [31:0] rd_val;
    bit        ok;
    phase.raise_objection(this);

    $display("===================================================Test_073 : AXI Handshake Scenario Coverage - Start=================================================================");

    wr_seq = accel_csr_write_seq::type_id::create("wr_seq");
    rd_seq = accel_csr_read_seq::type_id::create("rd_seq");
    env.sco.flush_queues();

    // ---- Initial reset ----
    $display("                Step 1 : Soft Reset + Clear                 ");
    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0048;
    wr_seq.start(env.axil_a.seqr);
    repeat(10) @(posedge axil_vif.clk);
    
    wr_seq.csr_data = 32'h0000_0008;
    wr_seq.start(env.axil_a.seqr);
    repeat(5)  @(posedge axil_vif.clk);

    // ---- Pat 1 : valid‑first standard write ----
    $display("                Pattern 1 : Valid‑first standard write                ");
    wr_seq.csr_addr = CSR_TILE_CFG;
    wr_seq.csr_data = 32'h0001_0008;
    wr_seq.start(env.axil_a.seqr);
    
    env.sco.set_expected(CSR_TILE_CFG, 32'h0001_0008);
    rd_seq.csr_addr = CSR_TILE_CFG;
    rd_seq.start(env.axil_a.seqr);

    // ---- Pat 2 : ready‑first (BREADY pre‑asserted) ----
    $display("                Pattern 2 : Ready‑first (BREADY pre‑asserted)                ");
    @(posedge axil_vif.clk);
    axil_vif.drv_cp.bready <= 1;
    @(posedge axil_vif.clk);
    // Drive AW + W together
    axil_vif.drv_cp.awaddr  <= CSR_SPARSITY;
    axil_vif.drv_cp.awvalid <= 1;
    axil_vif.drv_cp.wdata   <= 32'h0000_0002;
    axil_vif.drv_cp.wstrb   <= 4'hF;
    axil_vif.drv_cp.wvalid  <= 1;
    @(posedge axil_vif.clk iff axil_vif.mon_cp.awready && axil_vif.mon_cp.wready);
    axil_vif.drv_cp.awvalid <= 0;
    axil_vif.drv_cp.wvalid  <= 0;
    @(posedge axil_vif.clk iff axil_vif.mon_cp.bvalid);
    axil_vif.drv_cp.bready  <= 0;
    // Verify SPARSITY = 2
    env.sco.set_expected(CSR_SPARSITY, 32'h0000_0002);
    rd_seq.csr_addr = CSR_SPARSITY;
    rd_seq.start(env.axil_a.seqr);

    // ---- Pat 3 : simultaneous rapid writes (10 pairs) ----
    $display("                Pattern 3 : Simultaneous rapid writes (10 pairs)                ");
    for (int i = 0; i < 10; i++) begin
      wr_seq.csr_addr = CSR_IRQ_EN;
      wr_seq.csr_data = 32'h0000_0001;
      wr_seq.start(env.axil_a.seqr);
      
      wr_seq.csr_data = 32'h0000_0000;
      wr_seq.start(env.axil_a.seqr);
    end
    env.sco.set_expected(CSR_IRQ_EN, 32'h0000_0000);
    rd_seq.csr_addr = CSR_IRQ_EN;
    rd_seq.start(env.axil_a.seqr);

    // ---- Pat 4 : BREADY backpressure (50 cycles) ----
    $display("                Pattern 4 : BREADY backpressure 50 cycles                ");
    @(posedge axil_vif.clk);
    axil_vif.drv_cp.awaddr  <= CSR_PP_CTRL;
    axil_vif.drv_cp.awvalid <= 1;
    axil_vif.drv_cp.wdata   <= 32'h0000_0000;
    axil_vif.drv_cp.wstrb   <= 4'hF;
    axil_vif.drv_cp.wvalid  <= 1;
    axil_vif.drv_cp.bready  <= 0;
    @(posedge axil_vif.clk iff axil_vif.mon_cp.awready && axil_vif.mon_cp.wready);
    axil_vif.drv_cp.awvalid <= 0;
    axil_vif.drv_cp.wvalid  <= 0;
    // hold BREADY low for 50 cycles
    repeat(50) @(posedge axil_vif.clk);
    axil_vif.drv_cp.bready  <= 1;
    @(posedge axil_vif.clk iff axil_vif.mon_cp.bvalid && axil_vif.mon_cp.bready);
    axil_vif.drv_cp.bready  <= 0;
    $display("    BREADY backpressure passed (no hang).");

    // ---- Pat 5 : RREADY backpressure (20 cycles – shorter for runtime) ----
    $display("                Pattern 5 : RREADY backpressure 20 cycles                ");
    ok = 1;
    @(posedge axil_vif.clk);
    axil_vif.drv_cp.araddr  <= CSR_VERSION;
    axil_vif.drv_cp.arprot  <= 3'b000;
    axil_vif.drv_cp.arvalid <= 1;
    axil_vif.drv_cp.rready  <= 0;
    @(posedge axil_vif.clk iff axil_vif.mon_cp.arready);
    axil_vif.drv_cp.arvalid <= 0;
    repeat(20) begin
      @(posedge axil_vif.clk);
      if (!axil_vif.mon_cp.rvalid) ok = 0;
    end
    axil_vif.drv_cp.rready <= 1;
    @(posedge axil_vif.clk iff axil_vif.mon_cp.rvalid && axil_vif.mon_cp.rready);
    rd_val = axil_vif.mon_cp.rdata;
    axil_vif.drv_cp.rready <= 0;
    
    if (!ok)
      `uvm_error(get_name(), "RVALID dropped during RREADY=0!")
    else if (rd_val !== 32'h12040000)
      `uvm_error(get_name(), $sformatf("RDATA unstable! got=0x%08X", rd_val))
    else
      $display("    RREADY backpressure passed (RVALID stable, RDATA correct).");

    // ---- Final check: normal read still works ----
    $display("                Final : Normal read to verify no hang                ");
    env.sco.set_expected(CSR_VERSION, 32'h12040000);
    rd_seq.csr_addr = CSR_VERSION;
    rd_seq.start(env.axil_a.seqr);

    $display("===================================================Test_073 : End of the test=================================================================");
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass

`endif