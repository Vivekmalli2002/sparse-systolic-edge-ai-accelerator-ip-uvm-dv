`ifndef TEST_001_CSR_RESET_SANITY_SV
`define TEST_001_CSR_RESET_SANITY_SV


class test_001_CSR_reset_sanity extends base_test;

  `uvm_component_utils(test_001_CSR_reset_sanity)
  
  function new(string inst = "test_001_CSR_reset_sanity", uvm_component parent = null);
  
    super.new(inst,parent);
  
  endfunction
  
  
  virtual task run_phase(uvm_phase phase);
  
    phase.raise_objection(this);

    
    $display("===================================================Test_001: CSR Reset-Sanity - Start=================================================================");

    rd_seq = accel_csr_read_seq::type_id::create("rd_seq");

    env.sco.flush_queues();

    // Register expected reset values
    env.sco.set_expected(CSR_CTRL,       32'h0000_0000);
    env.sco.set_expected(CSR_STATUS,     32'h0000_0000);
    env.sco.set_expected(CSR_TILE_CFG,   32'h0008_0080);
    env.sco.set_expected(CSR_SPARSITY,   32'h0000_0001);
    env.sco.set_expected(CSR_IRQ_EN,     32'h0000_0000);
    env.sco.set_expected(CSR_IRQ_STATUS, 32'h0000_0018);
    env.sco.set_expected(CSR_VERSION,    32'h1204_0000);

    // Read each CSR — scoreboard checks automatically
    $display("                READ : CSR_CTRL REG                 ");

    rd_seq.csr_addr = CSR_CTRL;
    rd_seq.start(env.axil_a.seqr);

    $display("                READ : CSR_STATUS REG                 ");

    rd_seq.csr_addr = CSR_STATUS;
    rd_seq.start(env.axil_a.seqr);

    $display("                READ : CSR_TILE_CFG REG                 ");

    rd_seq.csr_addr = CSR_TILE_CFG;
    rd_seq.start(env.axil_a.seqr);

    $display("                READ : CSR_SPARSITY REG                 ");

    rd_seq.csr_addr = CSR_SPARSITY;
    rd_seq.start(env.axil_a.seqr);

    $display("                READ : CSR_IRQ_EN REG                 ");

    rd_seq.csr_addr = CSR_IRQ_EN;
    rd_seq.start(env.axil_a.seqr);

    $display("                READ : CSR_IRQ_STATUS REG                 ");

    rd_seq.csr_addr = CSR_IRQ_STATUS;
    rd_seq.start(env.axil_a.seqr);

    $display("                READ : CSR_VERSION REG                 ");

    rd_seq.csr_addr = CSR_VERSION;
    rd_seq.start(env.axil_a.seqr);

    $display("===================================================Test_001 : End of the test=================================================================");
    
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)

    phase.drop_objection(this);
  
  endtask


endclass



`endif