`ifndef ACCEL_SCOREBOARD_SV
`define ACCEL_SCOREBOARD_SV

// Declare unique suffixes for each analysis import
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
    logic [31:0] expected_map [logic [11:0]];

    // Computation checking queues
    axis_weight_tnx  weight_queue[$];
    axis_act_tnx     act_queue[$];

    // Statistics
    int pass_count;
    int fail_count;

    // ─────────────────────────────────────────────────────────
    // Post‑processing mirror (captured from CSR writes)
    // ─────────────────────────────────────────────────────────
    bit [2:0]  pp_op_sel;          // PP_CTRL[2:0]
    bit        pp_round_en;        // PP_CTRL[8]
    bit        pp_sat_en;          // PP_CTRL[9]
    bit [15:0] pp_scale;           // PP_SCALE (signed 16‑bit)
    bit [5:0]  pp_shift;           // PP_SHIFT
    bit [31:0] pp_sat_max;         // PP_SAT_MAX
    bit [31:0] pp_sat_min;         // PP_SAT_MIN
    bit [15:0] bias_mem [16];      // per‑column bias (INT16)
    bit [7:0]  bias_wr_ptr;        // auto‑increment pointer for bias loading

    bit [2:0]  activation_fn;      // from CSR_SPARSITY[5:3] or CSR_ACT_CFG[2:0]

    // ─────────────────────────────────────────────────────────
    // UVM essentials
    // ─────────────────────────────────────────────────────────
    function new(string name = "accel_scoreboard", uvm_component parent = null);
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

        // default post‑proc values (no operation)
        pp_op_sel   = 3'b000;
        pp_round_en = 0;
        pp_sat_en   = 0;
        pp_scale    = 16'd1;
        pp_shift    = 6'd0;
        pp_sat_max  = 32'h7FFF_FFFF;
        pp_sat_min  = 32'h8000_0000;
        activation_fn = 3'b000;
        bias_wr_ptr = 0;
    endfunction

    // ─────────────────────────────────────────────────────────
    // CSR expected value setup (called from test)
    // ─────────────────────────────────────────────────────────
    function void set_expected(logic [11:0] addr, logic [31:0] data);
        expected_map[addr] = data;
    endfunction

    // ─────────────────────────────────────────────────────────
    // AXI‑Lite write – also captures post‑proc configuration
    // ─────────────────────────────────────────────────────────
    function void write_axil(axil_csr_tnx t);
        if (t.we == 1) begin
            // always store for write‑readback tests
            expected_map[t.addr] = t.wdata;

            // capture post‑proc configuration
            case (t.addr)
                12'h0B0 : begin  // CSR_PP_CTRL
                    pp_op_sel   = t.wdata[2:0];
                    pp_round_en = t.wdata[8];
                    pp_sat_en   = t.wdata[9];
                end
                12'h0B4 : pp_scale = t.wdata[15:0];                // CSR_PP_SCALE
                12'h0B8 : pp_shift = t.wdata[5:0];                 // CSR_PP_SHIFT
                12'h0BC : pp_sat_max = t.wdata;                    // CSR_PP_SAT_MAX
                12'h0C0 : pp_sat_min = t.wdata;                    // CSR_PP_SAT_MIN
                12'h0E8 : bias_wr_ptr = t.wdata[7:0];              // CSR_PP_BIAS_ADDR
                12'h0EC : begin                                   // CSR_PP_BIAS_DATA
                    bias_mem[bias_wr_ptr] = t.wdata[15:0];
                    bias_wr_ptr++;
                end
                12'h00C : activation_fn = t.wdata[5:3];            // CSR_SPARSITY[5:3]
                12'h0A0 : activation_fn = t.wdata[2:0];            // CSR_ACT_CFG (override)
            endcase

            `uvm_info("SCO", $sformatf("WRITE addr=0x%0h data=0x%0h", t.addr, t.wdata), UVM_MEDIUM)
        end
        else begin
            // read – skip perf counters (monitoring only)
            if (t.addr >= 12'h030 && t.addr <= 12'h040) begin
                `uvm_info("SCO", $sformatf("PERF READ addr=0x%0h data=0x%0h", t.addr, t.rdata), UVM_HIGH)
                return;
            end

            if (!expected_map.exists(t.addr)) begin
                `uvm_warning("SCO", $sformatf("READ addr=0x%0h no expected registered", t.addr))
                return;
            end

            if (t.rdata === expected_map[t.addr]) begin
                pass_count++;
                `uvm_info("SCO", $sformatf("PASS addr=0x%0h exp=0x%0h got=0x%0h", t.addr, expected_map[t.addr], t.rdata), UVM_MEDIUM)
            end
            else begin
                fail_count++;
                `uvm_error("SCO", $sformatf("FAIL addr=0x%0h exp=0x%0h got=0x%0h", t.addr, expected_map[t.addr], t.rdata))
            end
        end
    endfunction

  
    int   expected_results_per_weight = 0;   // 0 ⇒ use t.last
    int   results_received_for_weight = 0;

    function void set_expected_results_per_weight(int count);
        expected_results_per_weight = count;
        results_received_for_weight = 0;
    endfunction
  
  
    // ─────────────────────────────────────────────────────────
    // Weight / Activation / Result handlers
    // ─────────────────────────────────────────────────────────
    function void write_weight(axis_weight_tnx t);
        weight_queue.push_back(t);
        `uvm_info("SCO", $sformatf("Weight tile stored — queue=%0d", weight_queue.size()), UVM_MEDIUM)
    endfunction

    function void write_act(axis_act_tnx t);
        act_queue.push_back(t);
        `uvm_info("SCO", $sformatf("Act vector stored — queue=%0d", act_queue.size()), UVM_MEDIUM)
    endfunction

    function void write_result(axis_result_tnx t);
        axis_weight_tnx              w;
        axis_act_tnx                 a;
        logic signed [31:0]          expected [TB_COLS];  // raw psum before PP

        if (weight_queue.size() == 0) begin
            `uvm_fatal("SCO", "Result received but weight queue empty")
            return;
        end
        if (act_queue.size() == 0) begin
            `uvm_error("SCO", "Result received but act queue empty")
            return;
        end

        w = weight_queue[0];
        a = act_queue.pop_front();

        `uvm_info("SCO", $sformatf("Computing: w0[0]=%0d w1[0]=%0d a0=%0d a1=%0d", w.w0[0], w.w1[0], a.a0, a.a1), UVM_MEDIUM)

        // compute raw psum (before post‑processing)
        compute_expected(w, a, expected);

        // apply DUT’s post‑processing pipeline
        for (int c = 0; c < TB_COLS; c++)
            apply_postproc(expected[c], c);

        // compare with DUT outputs
        for (int c = 0; c < TB_COLS; c++) begin
            if (t.result[c] !== expected[c]) begin
                fail_count++;
                `uvm_error("SCO", $sformatf("MISMATCH col=%0d exp=0x%0h got=0x%0h", c, expected[c], t.result[c]))
            end
            else begin
                pass_count++;
            end
        end

        // Decide when to pop the weight queue
        results_received_for_weight++;
        if (expected_results_per_weight > 0) begin   // counter mode
            if (results_received_for_weight >= expected_results_per_weight) begin
                void'(weight_queue.pop_front());
                results_received_for_weight = 0;
                expected_results_per_weight = 0;
            end
        end else begin                              // legacy mode: pop on t.last
            if (t.is_last)
                void'(weight_queue.pop_front());
        end
            endfunction

    // ─────────────────────────────────────────────────────────
    // Reference model – raw psum W*X (no PP)
    // ─────────────────────────────────────────────────────────
    function void compute_expected(
        axis_weight_tnx              w,
        axis_act_tnx                 a,
        ref logic signed [31:0]      expected [TB_COLS]
    );
        logic signed [7:0] act[4];
        act[0] = a.a0; act[1] = a.a1; act[2] = a.a2; act[3] = a.a3;

        for (int c = 0; c < TB_COLS; c++) begin
            expected[c] = 0;
            for (int r = 0; r < TB_ROWS; r++) begin
                if (a.mode_dense) begin
                    expected[c] += w.w0[r*TB_COLS + c] * act[0];
                    expected[c] += w.w1[r*TB_COLS + c] * act[1];
                    expected[c] += w.w0[r*TB_COLS + c] * act[2];
                    expected[c] += w.w1[r*TB_COLS + c] * act[3];
                end else begin
                    automatic int i0 = w.idx0[r*TB_COLS + c];
                    expected[c] += w.w0[r*TB_COLS + c] * act[i0];
                    // only add w1 for 2:4 and 4:8; 1:4 ignores w1
                    if (w.sparsity_mode != SPARSITY_1_4) begin
                        automatic int i1 = w.idx1[r*TB_COLS + c];
                        expected[c] += w.w1[r*TB_COLS + c] * act[i1];
                    end
                end
            end
        end
    endfunction

    // ─────────────────────────────────────────────────────────
    // Post‑processing pipeline (mirrors DUT)
    //     deskew → activation_fn → bias → scale → shift+round+saturate
    // ─────────────────────────────────────────────────────────
    function automatic void apply_postproc(
        ref logic signed [31:0] val,
        input int               col
    );
        longint tmp;  // 64‑bit intermediate to avoid overflow

        // 1. Activation function (ReLU / ReLU6 / Leaky ReLU)
        case (activation_fn)
            3'b001: begin // ReLU
                if (val < 0) val = 0;
            end
            3'b010: begin // ReLU6 (6 in Q8 fixed‑point = 1536)
                if (val < 0)       val = 0;
                if (val > 32'd1536) val = 32'd1536;
            end
            3'b011: begin // Leaky ReLU (α ≈ 0.125 = >>>3)
                if (val < 0) val = val >>> 3;
            end
            default: ; // ACT_NONE / others – pass through
        endcase

        // 2. Bias addition (if selected by op_sel)
        if (pp_op_sel inside {3'b001, 3'b011, 3'b100}) begin  // PP_BIAS_ADD, PP_REQUANT, PP_BIAS_SCALE
            // sign‑extend 16‑bit bias to 32‑bit and add
            val = val + signed'(bias_mem[col]);
        end

        // 3. Scale + Shift + Round + Saturate
        if (pp_op_sel inside {3'b010, 3'b011, 3'b100}) begin  // PP_SCALE_SHIFT, PP_REQUANT, PP_BIAS_SCALE
            // scale (signed 16‑bit)
            tmp = longint'(val) * longint'(signed'(pp_scale));

            // rounding
            if (pp_round_en && pp_shift > 0)
                tmp = tmp + (1 << (pp_shift - 1));

            // arithmetic right shift
            val = tmp >>> pp_shift;
        end

        // 4. Saturation (only when op_sel is not PP_NONE)
        if (pp_sat_en && pp_op_sel != 3'b000) begin
            if (val > signed'(pp_sat_max)) val = signed'(pp_sat_max);
            if (val < signed'(pp_sat_min)) val = signed'(pp_sat_min);
        end
    endfunction

    // ─────────────────────────────────────────────────────────
    // Helpers
    // ─────────────────────────────────────────────────────────
    function void flush_queues();
        weight_queue.delete();
        act_queue.delete();
        `uvm_info("SCO", "Queues flushed", UVM_MEDIUM)
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCO", $sformatf("FINAL: pass=%0d fail=%0d", pass_count, fail_count), UVM_NONE)
        if (fail_count > 0)
            `uvm_error("SCO", "TEST FAILED")
        else
            `uvm_info("SCO", "TEST PASSED", UVM_NONE)
    endfunction

endclass

`endif