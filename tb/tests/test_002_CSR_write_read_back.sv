`ifndef TEST_002_CSR_WRITE_READ_BACK_SV
`define TEST_002_CSR_WRITE_READ_BACK_SV


class test_002_CSR_write_read_back extends base_test;

  `uvm_component_utils(test_002_CSR_write_read_back)
  
  function new(string inst = "test_002_CSR_write_read_back", uvm_component parent = null);
  
    super.new(inst,parent);
  
  endfunction
  
  
  virtual task run_phase(uvm_phase phase);
  
    phase.raise_objection(this);

    
    $display("===================================================Test_002: CSR Write-Readback - Start=================================================================");


    wr_seq = accel_csr_write_seq::type_id::create("wr_seq");
    rd_seq = accel_csr_read_seq::type_id::create("rd_seq");
    
    env.sco.flush_queues();

    //CSR_TILE_CFG
    $display("                WRITE : CSR_TILE_CFG REG                 ");

    wr_seq.csr_addr = CSR_TILE_CFG;
    wr_seq.csr_data = 32'h0032_0032;

    wr_seq.start(env.axil_a.seqr);

    $display("                READ : CSR_TILE_CFG REG                 ");

    rd_seq.csr_addr = CSR_TILE_CFG;

    rd_seq.start(env.axil_a.seqr);


    //CSR_SPARSITY
    $display("                WRITE : CSR_SPARSITY REG                 ");

    wr_seq.csr_addr = CSR_SPARSITY;
    wr_seq.csr_data = 32'h0000_000D;

    wr_seq.start(env.axil_a.seqr);

    $display("                READ : CSR_SPARSITY REG                 ");

    rd_seq.csr_addr = CSR_SPARSITY;

    rd_seq.start(env.axil_a.seqr);


    //CSR_IRQ_EN
    $display("                WRITE : CSR_IRQ_EN  REG                 ");

    wr_seq.csr_addr = CSR_IRQ_EN;
    wr_seq.csr_data = 32'h0000_0009;

    wr_seq.start(env.axil_a.seqr);

    $display("                READ : CSR_IRQ_EN  REG                 ");

    rd_seq.csr_addr = CSR_IRQ_EN;

    rd_seq.start(env.axil_a.seqr);


    //CSR_PP_CTRL
    $display("                WRITE : CSR_PP_CTRL   REG                 ");

    wr_seq.csr_addr = CSR_PP_CTRL;
    wr_seq.csr_data = 32'h0000_0184;

    wr_seq.start(env.axil_a.seqr);

    $display("                READ : CSR_PP_CTRL   REG                 ");

    rd_seq.csr_addr = CSR_PP_CTRL;

    rd_seq.start(env.axil_a.seqr);


    //CSR_PP_SCALE
    $display("                WRITE : CSR_PP_SCALE   REG                 ");

    wr_seq.csr_addr = CSR_PP_SCALE;
    wr_seq.csr_data = 32'h0000_0002;

    wr_seq.start(env.axil_a.seqr);

    $display("                READ : CSR_PP_SCALE   REG                 ");

    rd_seq.csr_addr = CSR_PP_SCALE;

    rd_seq.start(env.axil_a.seqr);


    //CSR_PP_SAT_MAX
    $display("                WRITE : CSR_PP_SAT_MAX    REG                 ");

    wr_seq.csr_addr = CSR_PP_SAT_MAX;
    wr_seq.csr_data = 32'h0000_00FF;

    wr_seq.start(env.axil_a.seqr);

    $display("                READ : CSR_PP_SAT_MAX    REG                 ");

    rd_seq.csr_addr = CSR_PP_SAT_MAX;

    rd_seq.start(env.axil_a.seqr);


    //CSR_PP_SAT_MIN
    $display("                WRITE : CSR_PP_SAT_MIN    REG                 ");

    wr_seq.csr_addr = CSR_PP_SAT_MIN;
    wr_seq.csr_data = 32'hFFFF_FF00;

    wr_seq.start(env.axil_a.seqr);

    $display("                READ : CSR_PP_SAT_MIN    REG                 ");

    rd_seq.csr_addr = CSR_PP_SAT_MIN;

    rd_seq.start(env.axil_a.seqr);


    $display("===================================================Test_002 : End of the test=================================================================");

    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)

    phase.drop_objection(this);
  
  endtask


endclass



`endif