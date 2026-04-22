`ifndef ACCEL_SEQUENCES_SV
`define ACCEL_SEQUENCES_SV


class accel_csr_write_seq extends uvm_sequence #(axil_csr_tnx);

    `uvm_object_utils(accel_csr_write_seq)

    // Test sets these before calling start()
    logic [11:0] csr_addr;
    logic [31:0] csr_data;

    axil_csr_tnx t;

    function new(string name = "accel_csr_write_seq");

        super.new(name);

    endfunction

    task body();
        t = axil_csr_tnx::type_id::create("t");

        start_item(t);
        // Set directed fields — addr and we are not rand
        t.addr  = csr_addr;
        t.wdata = csr_data;
        t.we    = 1;
        finish_item(t);

        `uvm_info("CSR_WRITE_SEQ",$sformatf("Written addr=0x%0h data=0x%0h",t.addr, t.wdata), UVM_MEDIUM)
    endtask

endclass


class accel_csr_read_seq extends uvm_sequence #(axil_csr_tnx);

  `uvm_object_utils(accel_csr_read_seq)

  // Test sets these before calling start()
  logic [11:0] csr_addr;

  axil_csr_tnx t;

  function new(string name = "accel_csr_read_seq");

        super.new(name);

  endfunction

  task body();

    t = axil_csr_tnx::type_id::create("t");

    start_item(t);
    // Set directed fields — addr and we are not rand
    t.addr  = csr_addr;
    t.we    = 0;
    finish_item(t);

    `uvm_info("CSR_READ_SEQ",$sformatf("Written addr=0x%0h ",t.addr), UVM_MEDIUM)

  endtask

endclass


class accel_configure_seq extends uvm_sequence #(axil_csr_tnx);

    `uvm_object_utils(accel_configure_seq)

    // Configuration parameters — test sets these
    logic [31:0] tile_cfg;      // rows and cols config
    logic [31:0] sparsity_cfg;  // sparsity mode
    logic [31:0] pp_ctrl;       // post-processing control


    function new(string name = "accel_configure_seq");

        super.new(name);

    endfunction


    task body();

        accel_csr_write_seq wr_seq;

        // Write TILE_CFG
        wr_seq = accel_csr_write_seq::type_id::create("wr_seq");
        wr_seq.csr_addr = CSR_TILE_CFG;
        wr_seq.csr_data = tile_cfg;
        wr_seq.start(get_sequencer());

        // Write SPARSITY
        wr_seq = accel_csr_write_seq::type_id::create("wr_seq");
        wr_seq.csr_addr = CSR_SPARSITY;
        wr_seq.csr_data = sparsity_cfg;
        wr_seq.start(get_sequencer());

        // Write PP_CTRL
        wr_seq = accel_csr_write_seq::type_id::create("wr_seq");
        wr_seq.csr_addr = CSR_PP_CTRL;
        wr_seq.csr_data = pp_ctrl;
        wr_seq.start(get_sequencer());

        // Write CTRL — start computation
        wr_seq = accel_csr_write_seq::type_id::create("wr_seq");
        wr_seq.csr_addr = CSR_CTRL;
        wr_seq.csr_data = 32'h0000_0001;
        wr_seq.start(get_sequencer());

        `uvm_info("CONFIGURE_SEQ", "DUT configured", UVM_MEDIUM)

    endtask


endclass


`endif