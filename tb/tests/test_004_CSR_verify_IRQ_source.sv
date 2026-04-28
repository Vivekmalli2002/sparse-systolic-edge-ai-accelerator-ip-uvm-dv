`ifndef TEST_004_CSR_VERIFY_IRQ_SOURCE_SV
`define TEST_004_CSR_VERIFY_IRQ_SOURCE_SV


class test_004_CSR_verify_IRQ_source extends base_test;

  `uvm_component_utils(test_004_CSR_verify_IRQ_source)
  
  function new(string inst = "test_004_CSR_verify_IRQ_source", uvm_component parent = null);
  
    super.new(inst,parent);
  
  endfunction
  
  
  virtual task run_phase(uvm_phase phase);
  
    phase.raise_objection(this);


    $display("===================================================Test_004: CSR IRQ Sources - Start=================================================================");
    
    wr_seq = accel_csr_write_seq::type_id::create("wr_seq");
    rd_seq = accel_csr_read_seq::type_id::create("rd_seq");
    
    env.sco.flush_queues();
    
    //Step 1 : Enable IRQ_COMPUTE_DONE in CSR_IRQ_EN
    
    $display("                WRITE : CSR_IRQ_EN REG                 ");
    
    wr_seq.csr_addr = CSR_IRQ_EN;
    wr_seq.csr_data = 32'h0000_0001;
    wr_seq.start(env.axil_a.seqr);    
    
    //Step 2 : Force IRQ_COMPUTE_DONE via IRQ_FORCE
    
    $display("                WRITE : CSR_IRQ_FORCE REG                 ");
    
    wr_seq.csr_addr = CSR_IRQ_FORCE;
    wr_seq.csr_data = 32'h0000_0001;
    wr_seq.start(env.axil_a.seqr);
    
    //Step 3 : Read CSR_IRQ_STATUS
    
    $display("                READ : CSR_IRQ_STATUS REG                 ");
    
    env.sco.set_expected(CSR_IRQ_STATUS, 32'h0000_0018);
    rd_seq.csr_addr = CSR_IRQ_STATUS;
    rd_seq.start(env.axil_a.seqr);
    
    //Step 4 : Clear IRQ_COMPUTE_DONE via W1C
    
    $display("                WRITE : CSR_IRQ_STATUS REG                 ");
    
    wr_seq.csr_addr = CSR_IRQ_STATUS;
    wr_seq.csr_data = 32'h0000_0001;
    wr_seq.start(env.axil_a.seqr);
    
    //Step 5 : Read CSR_IRQ_STATUS
    
    $display("                READ : CSR_IRQ_STATUS REG                 ");
    
    env.sco.set_expected(CSR_IRQ_STATUS, 32'h0000_0018);
    rd_seq.csr_addr = CSR_IRQ_STATUS;
    rd_seq.start(env.axil_a.seqr);
    
    //Step 6 : Disable all IRQs
    
    $display("                WRITE : CSR_IRQ_EN REG                 ");
    
    wr_seq.csr_addr = CSR_IRQ_EN;
    wr_seq.csr_data = 32'h0000_0000;
    wr_seq.start(env.axil_a.seqr);
    
    //Step 7 : Read CSR_IRQ_EN
    
    $display("                READ : CSR_IRQ_EN REG                 ");
    
    env.sco.set_expected(CSR_IRQ_EN, 32'h0000_0000);
    rd_seq.csr_addr = CSR_IRQ_EN;
    rd_seq.start(env.axil_a.seqr);
    
    
    $display("===================================================Test_004 : End of the test=================================================================");
    
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)

    phase.drop_objection(this);
  
  endtask


endclass



`endif