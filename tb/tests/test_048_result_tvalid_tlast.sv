`ifndef TEST_048_RESULT_TVALID_TLAST_SV
`define TEST_048_RESULT_TVALID_TLAST_SV

class test_048_result_tvalid_tlast extends base_test;
  `uvm_component_utils(test_048_result_tvalid_tlast)

  function new(string name = "test_048_result_tvalid_tlast", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    int total_beats = 0;
    int tlast_count = 0;
    bit saw_final_tlast = 0;
    bit tvalid_drop = 0;
    phase.raise_objection(this);

    $display("===================================================Test_048 : Result TVALID Stability and TLAST Position - Start=================================================================");

    w_tile_seq   = accel_weight_tile_seq::type_id::create("w_tile_seq");
    a_stream_seq = accel_act_stream_seq::type_id::create("a_stream_seq");
    w_tile_tnx   = axis_weight_tnx::type_id::create("w_tile_tnx");
    a_stream_tnx = axis_act_tnx::type_id::create("a_stream_tnx");
    wr_seq       = accel_csr_write_seq::type_id::create("wr_seq");

    env.sco.flush_queues();

    // Build weight tile (all ones)
    for (int i = 0; i < TB_ROWS * TB_COLS; i++) begin
      w_tile_tnx.w0[i] = 1; w_tile_tnx.w1[i] = 1;
      w_tile_tnx.idx0[i] = 0; w_tile_tnx.idx1[i] = 1;
    end
    w_tile_tnx.sparsity_mode = SPARSITY_DENSE;
    w_tile_tnx.sparse_mask   = 4'hF;

    // Activation (a=1, 8 vectors)
    a_stream_tnx.a0 = 1; a_stream_tnx.a1 = 1;
    a_stream_tnx.a2 = 1; a_stream_tnx.a3 = 1;
    a_stream_tnx.is_last = 1'b0;
    a_stream_tnx.mode_dense = 1'b1;

    // Reset + Configure
    $display("                Step 1 : Soft Reset + Clear                 ");
    wr_seq.csr_addr = CSR_CTRL; 
    wr_seq.csr_data = 32'h0000_0048;
    wr_seq.start(env.axil_a.seqr);
    repeat(10) @(posedge vif.clk);
    
    wr_seq.csr_addr = CSR_CTRL; 
    wr_seq.csr_data = 32'h0000_0008; 
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);

    $display("                Step 2 : Configure 1 tile, 8 vectors, dense                ");
    wr_seq.csr_addr = CSR_TILE_CFG;  
    wr_seq.csr_data = 32'h0001_0008; 
    wr_seq.start(env.axil_a.seqr);
    
    wr_seq.csr_addr = CSR_ACT_TILE_CFG;
    wr_seq.csr_data = 32'h0001_0000; 
    wr_seq.start(env.axil_a.seqr);
    
    wr_seq.csr_addr = CSR_SPARSITY;  
    wr_seq.csr_data = 32'h0000_0001; 
    wr_seq.start(env.axil_a.seqr);
    
    wr_seq.csr_addr = CSR_CTRL;    
    wr_seq.csr_data = 32'h0000_0001;
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);

    // Stream weights
    $display("                Step 3 : Stream weights                 ");
    w_tile_seq.t = w_tile_tnx;
    w_tile_seq.start(env.weight_a.seqr);
    @(posedge vif.clk iff probe_if.wgt_buf_tile_ready);

    // Enable + Start
    $display("                Step 4 : Enable + Start                 ");
    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0003;
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);
    @(posedge vif.clk iff probe_if.state === S_STREAM);

    // Stream 8 activations + monitor result stream in parallel
    $display("                Step 5 : Stream 8 activations, monitor result TVALID/TLAST                ");
    fork
      begin : act_drive
        for (int v = 0; v < 8; v++) begin
          a_stream_tnx.is_last = (v == 7);
          a_stream_seq.t = a_stream_tnx;
          a_stream_seq.start(env.act_a.seqr);
        end
      end
      begin : result_mon
        virtual accel_axis_result_if res_vif = env.result_a.mon.vif;
        bit last_tvalid = 0;
        // Wait for first valid
        @(posedge res_vif.clk iff res_vif.mon_cp.tvalid);
        while (!saw_final_tlast) begin
          @(posedge res_vif.clk);
          if (res_vif.mon_cp.tvalid) begin
            // Check stability: if not ready and last_tvalid was 1, that's fine (it's still valid)
            if (res_vif.mon_cp.tready) begin
              total_beats++;
              if (res_vif.mon_cp.tlast) begin
                tlast_count++;
                // For 8 vectors × 16 cols = 128 results, 4 results per beat = 32 beats total
                if (total_beats == 32) begin
                  saw_final_tlast = 1;
                  $display("    TLAST at beat %0d — correct final position", total_beats);
                end
              end
            end else begin
              // Not ready, but valid must remain asserted
              if (!last_tvalid && total_beats > 0)
                tvalid_drop = 1;
            end
            last_tvalid = 1;
          end else begin
            // tvalid dropped while we were waiting for ready? That's a violation.
            if (last_tvalid && !res_vif.mon_cp.tready)
              tvalid_drop = 1;
            last_tvalid = 0;
          end
        end
      end
    join

    // Check results
    $display("                Step 6 : Check TVALID stability and TLAST position                ");
    if (tvalid_drop)
      `uvm_error(get_name(), "TVALID dropped before TREADY handshake!")
    else
      $display("    TVALID stability PASS");

    if (!saw_final_tlast)
      `uvm_error(get_name(), "TLAST not seen on final beat!")
    else
      $display("    TLAST position PASS (beat %0d)", total_beats);

    // Wait for done
    @(posedge vif.clk iff probe_if.done === 1'b1);
    repeat(10) @(posedge vif.clk);

    $display("===================================================Test_048 : End of the test=================================================================");
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass

`endif