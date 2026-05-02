`ifndef TEST_041_AXIL_AW_W_ORDERING_SV
`define TEST_041_AXIL_AW_W_ORDERING_SV

class test_041_axil_aw_w_ordering extends base_test;
  `uvm_component_utils(test_041_axil_aw_w_ordering)

  function new(string name = "test_041_axil_aw_w_ordering", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    $display("================================Test_041 : AXI-Lite AW/W Channel Ordering - Start=============================================");

    wr_seq = accel_csr_write_seq::type_id::create("wr_seq");
    rd_seq = accel_csr_read_seq::type_id::create("rd_seq");
    env.sco.flush_queues();

    // ---- Step 1 : Soft Reset + Clear (using standard sequence writes) ----
    $display("                Step 1 : Soft Reset + Clear                ");
    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0048;
    wr_seq.start(env.axil_a.seqr);
    repeat(10) @(posedge vif.clk);

    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0008;
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);

    // ---- Step 2 : Write TILE_CFG (standard AW+W simultaneous) ----
    $display("                Step 2 : Write CSR_TILE_CFG = 0x00020008 via standard handshake                ");
    wr_seq.csr_addr = CSR_TILE_CFG;
    wr_seq.csr_data = 32'h0002_0008;   // tile_count=2, vector_count=8
    wr_seq.start(env.axil_a.seqr);

    env.sco.set_expected(CSR_TILE_CFG, 32'h0002_0008);
    rd_seq.csr_addr = CSR_TILE_CFG;
    rd_seq.start(env.axil_a.seqr);

    // ---- Step 3 : Rapid back-to-back writes to 4 different registers (test channel independence) ----
    $display("                Step 3 : Rapid back-to-back writes to SPARSITY, IRQ_EN, PP_SCALE, PP_SHIFT                ");
    wr_seq.csr_addr = CSR_SPARSITY;
    wr_seq.csr_data = 32'h2;           // 2:4 sparse
    wr_seq.start(env.axil_a.seqr);

    wr_seq.csr_addr = CSR_IRQ_EN;
    wr_seq.csr_data = 32'h1;           // enable IRQ source 0
    wr_seq.start(env.axil_a.seqr);

    wr_seq.csr_addr = CSR_PP_SCALE;
    wr_seq.csr_data = 32'h0000_0002;
    wr_seq.start(env.axil_a.seqr);

    wr_seq.csr_addr = CSR_PP_SHIFT;
    wr_seq.csr_data = 32'h0000_0004;
    wr_seq.start(env.axil_a.seqr);

    // ---- Step 4 : Verify all 4 registers were correctly written ----
    $display("                Step 4 : Verify all 4 rapid writes via scoreboard reads                ");
    env.sco.set_expected(CSR_SPARSITY,   32'h2);
    rd_seq.csr_addr = CSR_SPARSITY;
    rd_seq.start(env.axil_a.seqr);

    env.sco.set_expected(CSR_IRQ_EN,     32'h1);
    rd_seq.csr_addr = CSR_IRQ_EN;
    rd_seq.start(env.axil_a.seqr);

    env.sco.set_expected(CSR_PP_SCALE,   32'h0000_0002);
    rd_seq.csr_addr = CSR_PP_SCALE;
    rd_seq.start(env.axil_a.seqr);

    env.sco.set_expected(CSR_PP_SHIFT,   32'h0000_0004);
    rd_seq.csr_addr = CSR_PP_SHIFT;
    rd_seq.start(env.axil_a.seqr);

    // ---- Step 5 : Write (SAT_MAX) then immediately read a different register (TILE_CFG) ----
    $display("                Step 5 : Write SAT_MAX then immediately read TILE_CFG (concurrent channels)                ");
    wr_seq.csr_addr = CSR_PP_SAT_MAX;
    wr_seq.csr_data = 32'h0000_007F;     // SAT_MAX = 127
    wr_seq.start(env.axil_a.seqr);

    // Read while B channel is still outstanding (scoreboard expects TILE_CFG value)
    env.sco.set_expected(CSR_TILE_CFG, 32'h0002_0008);
    rd_seq.csr_addr = CSR_TILE_CFG;
    rd_seq.start(env.axil_a.seqr);

    // Verify SAT_MAX also landed correctly
    env.sco.set_expected(CSR_PP_SAT_MAX, 32'h0000_007F);
    rd_seq.csr_addr = CSR_PP_SAT_MAX;
    rd_seq.start(env.axil_a.seqr);

    $display("===================================================Test_041 : End of the test=================================================================");
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
  
endclass

`endif