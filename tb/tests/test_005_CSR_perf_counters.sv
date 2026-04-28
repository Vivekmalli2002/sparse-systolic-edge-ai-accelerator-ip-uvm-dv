`ifndef TEST_005_CSR_PERF_COUNTERS_SV
`define TEST_005_CSR_PERF_COUNTERS_SV


class test_005_CSR_perf_counters extends base_test;

  `uvm_component_utils(test_005_CSR_perf_counters)
  
  function new(string inst = "test_005_CSR_perf_counters", uvm_component parent = null);
  
    super.new(inst,parent);
  
  endfunction
  
  
  virtual task run_phase(uvm_phase phase);
  
    phase.raise_objection(this);


    $display("===================================================Test_005: CSR PERF Counters - Start=================================================================");
    
    wr_seq = accel_csr_write_seq::type_id::create("wr_seq");
    rd_seq = accel_csr_read_seq::type_id::create("rd_seq");
    
    env.sco.flush_queues();
    
    //Step 1 : read all 5 counters and set_expected all counters to 0
    env.sco.set_expected(CSR_PERF_CYCLES, 32'h0000_0000);
    env.sco.set_expected(CSR_PERF_MAC, 32'h0000_0000);
    env.sco.set_expected(CSR_PERF_ZA, 32'h0000_0000);
    env.sco.set_expected(CSR_PERF_ZW, 32'h0000_0000);
    env.sco.set_expected(CSR_PERF_STALL, 32'h0000_0000);
    
    $display("                READ : CSR_PERF_CYCLES REG                 ");
    rd_seq.csr_addr = CSR_PERF_CYCLES;
    rd_seq.start(env.axil_a.seqr);
    
    $display("                READ : CSR_PERF_STALL REG                 ");
    rd_seq.csr_addr = CSR_PERF_STALL;
    rd_seq.start(env.axil_a.seqr);
    
    $display("                READ : CSR_PERF_MAC REG                 ");
    rd_seq.csr_addr = CSR_PERF_MAC;
    rd_seq.start(env.axil_a.seqr);

    $display("                READ : CSR_PERF_ZA REG                 ");
    rd_seq.csr_addr = CSR_PERF_ZA;
    rd_seq.start(env.axil_a.seqr);
    
    $display("                READ : CSR_PERF_ZW REG                 ");
    rd_seq.csr_addr = CSR_PERF_ZW;
    rd_seq.start(env.axil_a.seqr);
    
    
    //Step 2 : write CSR_CTRL = 0x01 (enable only)
    $display("                WRITE : CSR_CTRL REG                 ");
    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0001;
    wr_seq.start(env.axil_a.seqr);
    
    
    //Step 3 : Wait for 20 cycles
    $display("                WAIT : 20 Clock cycles                ");
    repeat(20) @(posedge vif.clk);
     
    
    //Step 4 : read all 5 counters and expected all counters to 0
    
    $display("                READ : CSR_PERF_CYCLES REG                 ");
    rd_seq.csr_addr = CSR_PERF_CYCLES;
    rd_seq.start(env.axil_a.seqr);
    
    $display("                READ : CSR_PERF_STALL REG                 ");
    rd_seq.csr_addr = CSR_PERF_STALL;
    rd_seq.start(env.axil_a.seqr);
    
    $display("                READ : CSR_PERF_MAC REG                 ");
    rd_seq.csr_addr = CSR_PERF_MAC;
    rd_seq.start(env.axil_a.seqr);

    $display("                READ : CSR_PERF_ZA REG                 ");
    rd_seq.csr_addr = CSR_PERF_ZA;
    rd_seq.start(env.axil_a.seqr);
    
    $display("                READ : CSR_PERF_ZW REG                 ");
    rd_seq.csr_addr = CSR_PERF_ZW;
    rd_seq.start(env.axil_a.seqr);
    
    
    //Step 5 : write CSR_CTRL = 0x00 (disable)
    $display("                WRITE : CSR_CTRL REG                 ");
    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0000;
    wr_seq.start(env.axil_a.seqr);
    
    $display("===================================================Test_005 : End of the test=================================================================");
    
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)

    phase.drop_objection(this);
  
  endtask


endclass



`endif