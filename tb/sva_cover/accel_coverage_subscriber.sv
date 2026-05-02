`ifndef ACCEL_COVERAGE_SUBSCRIBER_SV
`define ACCEL_COVERAGE_SUBSCRIBER_SV

class accel_coverage_subscriber extends uvm_component;
    `uvm_component_utils(accel_coverage_subscriber)

    //------------------------------------------------------------------
    // Analysis imports
    //------------------------------------------------------------------
    uvm_analysis_imp_axil   #(axil_csr_tnx,    accel_coverage_subscriber) axil_imp;
    uvm_analysis_imp_weight #(axis_weight_tnx,  accel_coverage_subscriber) weight_imp;
    uvm_analysis_imp_act    #(axis_act_tnx,     accel_coverage_subscriber) act_imp;
    uvm_analysis_imp_result #(axis_result_tnx,  accel_coverage_subscriber) result_imp;

    // Transaction handles
    axil_csr_tnx     axil_item;
    axis_weight_tnx  weight_item;
    axis_act_tnx     act_item;
    axis_result_tnx  result_item;

    // Probe interface for FSM mode sampling
    virtual accel_dut_probes_if  probe_if;

    //==================================================================
    // Covergroup 1 – AXI-Lite CSR
    //==================================================================
    covergroup cg_axil;
        option.per_instance = 1;
        cp_we: coverpoint axil_item.we {
            bins write = {1'b1};
            bins read  = {1'b0};
        }
        cp_wdata_lsb: coverpoint axil_item.wdata[0] {
            bins zero = {0}; bins one = {1};
        }
        cp_rdata_lsb: coverpoint axil_item.rdata[0] {
            bins zero = {0}; bins one = {1};
        }
        cp_resp: coverpoint axil_item.resp {
            bins okay   = {2'b00};
            bins slverr = {2'b10};
        }
        cross_we_wdata: cross cp_we, cp_wdata_lsb {
            // Ignore wdata during reads because the write bus is inactive
            ignore_bins read_wdata = binsof(cp_we.read); 
        }
        
        // ---> AND UPDATE THIS CROSS WHILE YOU ARE AT IT <---
        // (For the exact same reason, rdata is invalid during a write!)
        cross_we_rdata: cross cp_we, cp_rdata_lsb {
            ignore_bins write_rdata = binsof(cp_we.write);
        }
        cross_we_resp : cross cp_we, cp_resp;
    endgroup

    //==================================================================
    // Covergroup 2 – Weight tile
    //==================================================================
    covergroup cg_weight;
        option.per_instance = 1;
        cp_sparsity: coverpoint weight_item.sparsity_mode {
            bins dense  = {SPARSITY_DENSE};
            bins sp_2_4 = {SPARSITY_2_4};
            bins sp_1_4 = {SPARSITY_1_4};
            bins sp_4_8 = {SPARSITY_4_8};
        }
        cp_w0_zero: coverpoint (weight_item.w0[0] == 0) {
            bins zero={1}; bins non_zero={0};
        }
        cp_w1_zero: coverpoint (weight_item.w1[0] == 0) {
            bins zero={1}; bins non_zero={0};
        }
        cp_sparse_mask: coverpoint weight_item.sparse_mask {
            bins mask_0000 = {4'b0000};
            bins mask_1111 = {4'b1111};
            bins mask_1010 = {4'b1010};
            bins mask_0101 = {4'b0101};
            bins others    = default;
        }
        cp_idx0: coverpoint weight_item.idx0[0] {
            bins low = {[0:1]}; bins high = {[2:3]};
        }
        cross_sparsity_w0: cross cp_sparsity, cp_w0_zero;
        cross_sparsity_mask: cross cp_sparsity, cp_sparse_mask;
        cross_sparsity_idx0: cross cp_sparsity, cp_idx0;
    endgroup

    //==================================================================
    // Covergroup 3 – Activation vector
    //==================================================================
    covergroup cg_activation;
        option.per_instance = 1;
        cp_mode_dense: coverpoint act_item.mode_dense {
            bins dense={1}; bins sparse={0};
        }
        cp_is_last: coverpoint act_item.is_last {
            bins last={1}; bins not_last={0};
        }
        cp_a0_zero: coverpoint (act_item.a0 == 0) { bins zero={1}; bins non_zero={0}; }
        cp_a1_zero: coverpoint (act_item.a1 == 0) { bins zero={1}; bins non_zero={0}; }
        cp_a2_zero: coverpoint (act_item.a2 == 0) { bins zero={1}; bins non_zero={0}; }
        cp_a3_zero: coverpoint (act_item.a3 == 0) { bins zero={1}; bins non_zero={0}; }
        cp_all_zero: coverpoint (act_item.a0 == 0 && act_item.a1 == 0 &&
                                 act_item.a2 == 0 && act_item.a3 == 0) {
            bins all_zero={1}; bins non_zero={0};
        }
        cp_a0_neg: coverpoint act_item.a0[A_WIDTH-1] { bins positive={1'b0}; bins negative={1'b1}; }
        cp_a1_neg: coverpoint act_item.a1[A_WIDTH-1] { bins positive={1'b0}; bins negative={1'b1}; }
        cross_mode_last: cross cp_mode_dense, cp_is_last;
        cross_mode_allzero: cross cp_mode_dense, cp_all_zero;
        cross_last_allzero: cross cp_is_last, cp_all_zero;
        cross_mode_a0sign: cross cp_mode_dense, cp_a0_neg;
    endgroup

    //==================================================================
    // Covergroup 4 – Result vector
    //==================================================================
    covergroup cg_result;
        option.per_instance =1;
        cp_is_last: coverpoint result_item.is_last {
            bins last={1}; bins not_last={0};
        }
        cp_result0_zero: coverpoint (result_item.result[0] == 0) {
            bins zero={1}; bins non_zero={0};
        }
        cp_result_last_zero: coverpoint (result_item.result[TB_COLS-1] == 0) {
            bins zero={1}; bins non_zero={0};
        }
        cp_result0_neg: coverpoint result_item.result[0][ACC_WIDTH-1] {
            bins positive={1'b0}; bins negative={1'b1};
        }
        cross_last_zero: cross cp_is_last, cp_result0_zero;
        cross_last_neg:  cross cp_is_last, cp_result0_neg;
    endgroup

    //==================================================================
    // Covergroup 5 – FSM state × mode (manually sampled)
    //==================================================================
    covergroup cg_fsm;
        option.per_instance = 1;
        cp_state: coverpoint probe_if.state {
            bins idle   = {S_IDLE};
            bins load   = {S_LOAD_WEIGHTS};
            bins stream = {S_STREAM};
            bins drain  = {S_DRAIN};
            bins done_st = {S_DONE};
            bins error  = {S_ERROR};
            bins recovery  = {S_RECOVERY};
        }
        cp_mode: coverpoint probe_if.mode_dense {
            bins dense  = {1'b1};
            bins sparse = {1'b0};
        }
        cross_state_mode: cross cp_state, cp_mode;
    endgroup

    //==================================================================
    // Constructor – instantiate covergroups (including cg_fsm)
    //==================================================================
    function new(string name = "accel_coverage_subscriber", uvm_component parent = null);
        super.new(name, parent);
        cg_axil       = new();
        cg_weight     = new();
        cg_activation = new();
        cg_result     = new();
        cg_fsm        = new();    // created here, but event‑based sampling starts later
    endfunction

    //==================================================================
    // build_phase – instantiate analysis imports & get probe IF
    //==================================================================
    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        axil_imp   = new("axil_imp",   this);
        weight_imp = new("weight_imp", this);
        act_imp    = new("act_imp",    this);
        result_imp = new("result_imp", this);
        if (!uvm_config_db #(virtual accel_dut_probes_if)::get(this, "", "probe_if", probe_if))
            `uvm_fatal("COV", "Virtual probe_if not found in config_db")
    endfunction

    //==================================================================
    // run_phase – start a thread to manually sample cg_fsm every clock
    //==================================================================
    virtual task run_phase(uvm_phase phase);
        forever begin
            @(posedge probe_if.clk);
            cg_fsm.sample();
        end
    endtask

    //==================================================================
    // write_axil / write_weight / write_act / write_result
    //==================================================================
    function void write_axil(axil_csr_tnx t);
        axil_item = t;
        cg_axil.sample();
    endfunction

    function void write_weight(axis_weight_tnx t);
        weight_item = t;
        cg_weight.sample();
    endfunction

    function void write_act(axis_act_tnx t);
        act_item = t;
        cg_activation.sample();
    endfunction

    function void write_result(axis_result_tnx t);
        result_item = t;
        cg_result.sample();
    endfunction

    //==================================================================
    // report_phase – print final coverage percentages
    //==================================================================
    function void report_phase(uvm_phase phase);
        real total = (cg_axil.get_coverage() + cg_weight.get_coverage() +
                      cg_activation.get_coverage() + cg_result.get_coverage() +
                      cg_fsm.get_coverage()) / 5.0;
        `uvm_info("COV", "======================================", UVM_NONE)
        `uvm_info("COV", "   Functional Coverage Summary        ", UVM_NONE)
        `uvm_info("COV", "======================================", UVM_NONE)
        `uvm_info("COV", $sformatf("  AXI-Lite   : %0.1f%%", cg_axil.get_coverage()),       UVM_NONE)
        `uvm_info("COV", $sformatf("  Weight     : %0.1f%%", cg_weight.get_coverage()),     UVM_NONE)
        `uvm_info("COV", $sformatf("  Activation : %0.1f%%", cg_activation.get_coverage()), UVM_NONE)
        `uvm_info("COV", $sformatf("  Result     : %0.1f%%", cg_result.get_coverage()),     UVM_NONE)
        `uvm_info("COV", $sformatf("  FSM+Mode   : %0.1f%%", cg_fsm.get_coverage()),        UVM_NONE)
        `uvm_info("COV", $sformatf("  TOTAL      : %0.1f%%", total), UVM_NONE)
        `uvm_info("COV", "======================================", UVM_NONE)
    endfunction

endclass

`endif