`ifndef TEST_003_CSR_SOFT_RESET_SV
`define TEST_003_CSR_SOFT_RESET_SV


class test_003_CSR_soft_reset extends base_test;

  `uvm_component_utils(test_003_CSR_soft_reset)
  
  function new(string inst = "test_003_CSR_soft_reset", uvm_component parent = null);
  
    super.new(inst,parent);
  
  endfunction
  
  
  virtual task run_phase(uvm_phase phase);
  
    phase.raise_objection(this);

    
    $display("===================================================Test_003: CSR Soft-Reset - Start=================================================================");

    env.sco.flush_queues();

    wr_seq = accel_csr_write_seq::type_id::create("wr_seq");
    rd_seq = accel_csr_read_seq::type_id::create("rd_seq");
    
    // Step 1 — Trigger soft reset
    $display("                WRITE : CSR_CTRL REG                 ");
    
    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0004;
    
    wr_seq.start(env.axil_a.seqr);
    
    @(posedge vif.clk);
    
    // Register expected reset values
    
    // Step 2 — FSM should be S_IDLE after soft reset
    env.sco.set_expected(CSR_STATUS, 32'h0000_0000);
    
    // Read each CSR — scoreboard checks automatically
    $display("                READ : CSR_CTRL REG                 ");
    
    rd_seq.csr_addr = CSR_STATUS;
    rd_seq.start(env.axil_a.seqr);

    // Step 3 — CSR values preserved from T002 — NOT reset
    env.sco.set_expected(CSR_TILE_CFG,  32'h0032_0032);
    env.sco.set_expected(CSR_SPARSITY,  32'h0000_000D);
    env.sco.set_expected(CSR_IRQ_EN,    32'h0000_0009);
    env.sco.set_expected(CSR_PP_CTRL,   32'h0000_0184);
    env.sco.set_expected(CSR_PP_SCALE,  32'h0000_0002);

    // Read each CSR — scoreboard checks automatically
    $display("                READ : CSR_TILE_CFG REG                 ");
    
    rd_seq.csr_addr = CSR_TILE_CFG;
    rd_seq.start(env.axil_a.seqr);
    
    // Read each CSR — scoreboard checks automatically
    $display("                READ : CSR_SPARSITY REG                 ");

    rd_seq.csr_addr = CSR_SPARSITY;
    rd_seq.start(env.axil_a.seqr);
    
    // Read each CSR — scoreboard checks automatically
    $display("                READ : CSR_IRQ_EN REG                 ");

    rd_seq.csr_addr = CSR_IRQ_EN;
    rd_seq.start(env.axil_a.seqr);
    
    // Read each CSR — scoreboard checks automatically
    $display("                READ : CSR_PP_CTRL REG                 ");

    rd_seq.csr_addr = CSR_PP_CTRL;
    rd_seq.start(env.axil_a.seqr);
    
    // Read each CSR — scoreboard checks automatically
    $display("                READ : CSR_PP_SCALE REG                 ");

    rd_seq.csr_addr = CSR_PP_SCALE;
    rd_seq.start(env.axil_a.seqr);
    
    
    $display("===================================================Test_003 : End of the test=================================================================");
    
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)

    phase.drop_objection(this);
  
  endtask


endclass



`endif