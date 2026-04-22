`ifndef TESTS_SV
`define TESTS_SV

class accel_base_test extends uvm_test;

    `uvm_component_utils(accel_base_test)

    accel_env env;
    virtual accel_axil_if vif;

    function new(string name = "accel_base_test",uvm_component parent = null);

        super.new(name, parent);

    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        env = accel_env::type_id::create("env", this);
        if(!uvm_config_db #(virtual accel_axil_if)::get(this, "", "axil_if", vif))
            `uvm_fatal("BASE_TEST", "axil_if not found")

    endfunction


    // Reusable — every child test calls this
    task wait_for_reset();

        @(posedge vif.clk iff vif.rst_n === 1);

        repeat(5) @(posedge vif.clk);
        `uvm_info("BASE_TEST", "Reset done — DUT ready", UVM_MEDIUM)

        $display("=========================================================================================================================================");

    endtask

    // Base run_phase is empty
    // Each child test implements its own run_phase
    virtual task run_phase(uvm_phase phase);
    endtask

endclass



class accel_sanity_test extends accel_base_test;

  `uvm_component_utils(accel_sanity_test)

  accel_csr_read_seq rd_seq;
  accel_csr_write_seq wr_seq;


  function new(string inst = "accel_sanity_test", uvm_component parent = null);

    super.new(inst,parent);

  endfunction


  virtual task run_phase(uvm_phase phase);

    phase.raise_objection(this);

    wait_for_reset();

    Test_001_CSR_ResetSanity();
    Test_001_CSR_WriteReadBack();


    phase.drop_objection(this);

  endtask


  task Test_001_CSR_ResetSanity();

     $display("===================================================T001: CSR Reset-Sanity - Start=================================================================");

    rd_seq = accel_csr_read_seq::type_id::create("rd_seq");


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

    $display("===================================================Test001 : End of the test=================================================================");

  endtask


  task Test_001_CSR_WriteReadBack();

    $display("===================================================T002: CSR Write-Readback - Start=================================================================");


    wr_seq = accel_csr_write_seq::type_id::create("wr_seq");
    rd_seq = accel_csr_read_seq::type_id::create("rd_seq");

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


    $display("===================================================Test002 : End of the test=================================================================");


  endtask


endclass

`endif