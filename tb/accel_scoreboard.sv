`ifndef ACCEL_SCOREBOARD_SV
`define ACCEL_SCOREBOARD_SV

`uvm_analysis_imp_decl(_axil)
`uvm_analysis_imp_decl(_weight)
`uvm_analysis_imp_decl(_act)
`uvm_analysis_imp_decl(_result)

class accel_scoreboard extends uvm_scoreboard;

    `uvm_component_utils(accel_scoreboard)

    // Analysis imports — one per monitor
    uvm_analysis_imp_axil   #(axil_csr_tnx, accel_scoreboard) axil_imp;
    uvm_analysis_imp_weight #(axis_weight_tnx, accel_scoreboard) weight_imp;
    uvm_analysis_imp_act    #(axis_act_tnx, accel_scoreboard) act_imp;
    uvm_analysis_imp_result #(axis_result_tnx, accel_scoreboard) result_imp;

    // CSR expected value storage
    // Populated by set_expected() for reset checks
    // OR auto-populated when write transaction seen
    logic [31:0] expected_map [logic [11:0]];

    // Computation checking queues
    axis_weight_tnx  weight_queue[$];
    axis_act_tnx     act_queue[$];

    // Statistics
    int pass_count;
    int fail_count;

    function new(string name = "accel_scoreboard",uvm_component parent = null);

        super.new(name, parent);

    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);

        axil_imp   = new("axil_imp",   this);
        weight_imp = new("weight_imp", this);
        act_imp    = new("act_imp",    this);
        result_imp = new("result_imp", this);
        pass_count = 0;
        fail_count = 0;

    endfunction

    // =====================================================
    // Test calls this to register CSR reset default values
    // =====================================================
    function void set_expected(
        logic [11:0] addr,
        logic [31:0] data
    );

        expected_map[addr] = data;

    endfunction

    // =====================================================
    // AXI-Lite monitor → CSR checking
    // =====================================================
    function void write_axil(axil_csr_tnx t);

        if(t.we == 1) begin
            // Auto-store write data — used for write-readback tests
            expected_map[t.addr] = t.wdata;
            `uvm_info("SCO",$sformatf("WRITE addr=0x%0h data=0x%0h",t.addr, t.wdata), UVM_MEDIUM)
        end
        else begin
            // Read — compare against expected
            if(!expected_map.exists(t.addr)) begin
                `uvm_warning("SCO",$sformatf("READ addr=0x%0h no expected registered",t.addr))
                return;
            end
            if(t.rdata === expected_map[t.addr]) begin
                pass_count++;
                `uvm_info("SCO",$sformatf("PASS addr=0x%0h exp=0x%0h got=0x%0h",t.addr, expected_map[t.addr], t.rdata), UVM_MEDIUM)
            end
            else begin
                fail_count++;
                `uvm_error("SCO",$sformatf("FAIL addr=0x%0h exp=0x%0h got=0x%0h",t.addr, expected_map[t.addr], t.rdata))
            end
        end


    endfunction

    // =====================================================
    // Weight monitor → store tile for computation check
    // =====================================================
    function void write_weight(axis_weight_tnx t);

        weight_queue.push_back(t);
        `uvm_info("SCO",$sformatf("Weight tile stored — queue=%0d",weight_queue.size()), UVM_HIGH)

    endfunction

    // =====================================================
    // Activation monitor → store vector for computation check
    // =====================================================
    function void write_act(axis_act_tnx t);

        act_queue.push_back(t);
        `uvm_info("SCO",$sformatf("Act vector stored — queue=%0d",act_queue.size()), UVM_HIGH)

    endfunction

    // =====================================================
    // Result monitor → trigger comparison
    // =====================================================
    function void write_result(axis_result_tnx t);

        axis_weight_tnx              w;
        axis_act_tnx                 a;
        logic signed [ACC_WIDTH-1:0] expected[TB_COLS];

        // Safety checks
        if(weight_queue.size() == 0) begin
            `uvm_fatal("SCO", "Result received but weight queue empty")
            return;
        end
        if(act_queue.size() == 0) begin
            `uvm_fatal("SCO", "Result received but act queue empty")
            return;
        end

        // Get weight — stays in queue until tile done
        w = weight_queue[0];

        // Get activation — consumed one per result vector
        a = act_queue.pop_front();

        // Compute expected Y = WX
        compute_expected(w, a, expected);

        // Compare each column
        for(int c = 0; c < TB_COLS; c++) begin
            if(t.result[c] !== expected[c]) begin
                fail_count++;
                `uvm_error("SCO",$sformatf("MISMATCH col=%0d exp=0x%0h got=0x%0h",c, expected[c], t.result[c]))
            end
            else begin
                pass_count++;
                `uvm_info("SCO",$sformatf("PASS col=%0d val=0x%0h",c, t.result[c]), UVM_HIGH)
            end
        end

        // Remove weight when tile complete
        if(t.is_last)
            void'(weight_queue.pop_front());

    endfunction

    // =====================================================
    // Reference model — Y = WX
    // Placeholder — replaced by Python vectors later
    // =====================================================
    function void compute_expected(
        axis_weight_tnx              w,
        axis_act_tnx                 a,
        ref logic signed [ACC_WIDTH-1:0] expected[TB_COLS]
    );

        logic signed [A_WIDTH-1:0] act[4];
        act[0] = a.a0;
        act[1] = a.a1;
        act[2] = a.a2;
        act[3] = a.a3;

        for(int c = 0; c < TB_COLS; c++) begin
            expected[c] = 0;
            for(int r = 0; r < TB_ROWS; r++) begin
                automatic int idx;
                // w0 contribution
                idx = w.idx0[r*TB_COLS+c];
                expected[c] += w.w0[r*TB_COLS+c] * act[idx];
                // w1 contribution
                idx = w.idx1[r*TB_COLS+c];
                expected[c] += w.w1[r*TB_COLS+c] * act[idx];
            end
        end

    endfunction

    // =====================================================
    // Final report
    // =====================================================
    function void report_phase(uvm_phase phase);

        `uvm_info("SCO",$sformatf("FINAL: pass=%0d fail=%0d",pass_count, fail_count), UVM_NONE)

        if(fail_count > 0)
            `uvm_error("SCO", "TEST FAILED")
        else
            `uvm_info("SCO", "TEST PASSED", UVM_NONE)

    endfunction

endclass

`endif