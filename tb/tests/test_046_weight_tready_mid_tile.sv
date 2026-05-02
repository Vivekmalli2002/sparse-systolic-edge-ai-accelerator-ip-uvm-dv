`ifndef TEST_046_WEIGHT_TREADY_MID_TILE_SV
`define TEST_046_WEIGHT_TREADY_MID_TILE_SV

class test_046_weight_tready_mid_tile extends base_test;
  `uvm_component_utils(test_046_weight_tready_mid_tile)

  function new(string name = "test_046_weight_tready_mid_tile", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    $display("=============================Test_046 : Weight Stream TREADY Mid-Tile De-assertion - Start=======================================");

    a_stream_seq = accel_act_stream_seq::type_id::create("a_stream_seq");
    a_stream_tnx = axis_act_tnx::type_id::create("a_stream_tnx");
    wr_seq       = accel_csr_write_seq::type_id::create("wr_seq");

    env.sco.flush_queues();

    // Activation vector (a=2, 1 vector)
    a_stream_tnx.a0 = 2; a_stream_tnx.a1 = 2;
    a_stream_tnx.a2 = 2; a_stream_tnx.a3 = 2;
    a_stream_tnx.is_last    = 1'b1;
    a_stream_tnx.mode_dense = 1'b1;

    // ---- Step 1 : Soft Reset + Clear ----
    $display("                Step 1 : Soft Reset + Clear                 ");
    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0048;
    wr_seq.start(env.axil_a.seqr);
    repeat(10) @(posedge vif.clk);
    
    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0008;
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);

    // ---- Step 2 : Configure 1 tile, 1 vector ----
    $display("                Step 2 : Configure 1 tile, 1 vector, dense                ");
    wr_seq.csr_addr = CSR_TILE_CFG;  
    wr_seq.csr_data = 32'h0001_0001;
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

    // ---- Step 3 : Manually stream weight tile with a 20-cycle gap after beat 3 ----
    $display("                Step 3 : Stream weight tile — pause TVALID for 20 cycles after beat 3                ");
    begin
      virtual accel_axis_weight_if wgt_vif = env.weight_a.drv.vif;
      // All-ones weight tile: 16 rows × 3 beats per row (for 16 columns, 6 pkts per beat)
      // Build the exact same packet data as the sequence would.
      // w0=1, w1=1, idx0=0, idx1=1 => 20'h40201
      bit [127:0] pkt;
      // For simplicity, we'll just reuse the sequence's driver logic by calling the sequence
      // but with a controllable gap? No, easier to manually drive the whole stream
      // with a small pause. Let's drive all beats, but after beat 3, wait 20 cycles.

      // We'll use the same loop structure as the weight driver:
      // For each row, for each beat, send a beat and wait for tready.
      // But we insert a delay after the 3rd beat.
      int beat_cnt = 0;
      for (int row = 0; row < TB_ROWS; row++) begin
        for (int b = 0; b < 3; b++) begin  // 3 beats per row (16 cols, ceil(16/6)=3 beats)
          // Build packet: fill up to 6 weight packets (each 20 bits)
          pkt = '0;
          for (int p = 0; p < 6; p++) begin
            int col = b*6 + p;
            if (col < TB_COLS) begin
              // w0=1, w1=1, idx0=0, idx1=1 => 20'b0000_0001_0000_0001_01? Wait need bit format.
              // weight packet: {idx1[1:0], idx0[1:0], w1[7:0], w0[7:0]}
              // idx1=1, idx0=0, w1=1, w0=1 -> {2'b01, 2'b00, 8'h01, 8'h01} = 20'h40201
              pkt[p*20 +: 20] = {2'd1, 2'd0, 8'd1, 8'd1};
            end
          end

          @(posedge wgt_vif.clk);
          wgt_vif.drv_cp.tdata  <= pkt;
          wgt_vif.drv_cp.tkeep  <= 16'hFFFF;
          wgt_vif.drv_cp.tvalid <= 1;
          wgt_vif.drv_cp.tuser  <= {4'h0, 2'b01, 1'b0, 1'b1};  // dense, last_in_tile=0, valid=1
          wgt_vif.drv_cp.tlast  <= (row == TB_ROWS-1) && (b == 2);

          // Wait for DUT to accept beat (tready)
          @(posedge wgt_vif.clk iff wgt_vif.mon_cp.tready);

          beat_cnt++;
          if (beat_cnt == 3) begin
            $display("    Pausing weight stream (TVALID=0) for 20 cycles");
            wgt_vif.drv_cp.tvalid <= 0;
            repeat(20) @(posedge wgt_vif.clk);
            $display("    Resuming weight stream");
            // On the next iteration of the loop, tvalid will be re-asserted with new data.
          end
        end
      end
      // Deassert tvalid at the end
      wgt_vif.drv_cp.tvalid <= 0;
    end

    // ---- Step 4 : Enable + Start ----
    $display("                Step 4 : Enable + Start                 ");
    wr_seq.csr_addr = CSR_CTRL; 
    wr_seq.csr_data = 32'h0000_0003;
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);
    @(posedge vif.clk iff probe_if.state === S_STREAM);

    // ---- Step 5 : Stream 1 activation vector ----
    $display("                Step 5 : Stream 1 activation vector                 ");
    a_stream_seq.t = a_stream_tnx;
    a_stream_seq.start(env.act_a.seqr);

    // ---- Step 6 : Wait for done ----
    $display("                Step 6 : Wait for computation done                 ");
    @(posedge vif.clk iff probe_if.done === 1'b1);
    repeat(10) @(posedge vif.clk);

    $display("===================================================Test_046 : End of the test=================================================================");
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass

`endif