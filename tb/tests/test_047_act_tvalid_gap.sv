`ifndef TEST_047_ACT_TVALID_GAP_SV
`define TEST_047_ACT_TVALID_GAP_SV

class test_047_act_tvalid_gap extends base_test;
  `uvm_component_utils(test_047_act_tvalid_gap)

  function new(string name = "test_047_act_tvalid_gap", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    $display("===================================================Test_047 : Activation TVALID Gap (Bubble) - Start=================================================================");

    w_tile_seq   = accel_weight_tile_seq::type_id::create("w_tile_seq");
    a_stream_seq = accel_act_stream_seq::type_id::create("a_stream_seq");
    w_tile_tnx   = axis_weight_tnx::type_id::create("w_tile_tnx");
    a_stream_tnx = axis_act_tnx::type_id::create("a_stream_tnx");
    wr_seq       = accel_csr_write_seq::type_id::create("wr_seq");

    env.sco.flush_queues();

    // ---- Build weight tile (all ones) ----
    for (int i = 0; i < TB_ROWS * TB_COLS; i++) begin
      w_tile_tnx.w0[i] = 1;  w_tile_tnx.w1[i] = 1;
      w_tile_tnx.idx0[i] = 0; w_tile_tnx.idx1[i] = 1;
    end
    w_tile_tnx.sparsity_mode = SPARSITY_DENSE;
    w_tile_tnx.sparse_mask   = 4'hF;

    // Activation vector (a=3 for all vectors)
    a_stream_tnx.a0 = 3; a_stream_tnx.a1 = 3;
    a_stream_tnx.a2 = 3; a_stream_tnx.a3 = 3;
    a_stream_tnx.is_last    = 1'b0;
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

    // ---- Step 2 : Configure 1 tile, 8 vectors, dense mode ----
    $display("                Step 2 : Configure 1 tile, 8 vectors, dense mode                ");
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

    // ---- Step 3 : Stream weights ----
    $display("                Step 3 : Stream weights (all-ones)                ");
    w_tile_seq.t = w_tile_tnx;
    w_tile_seq.start(env.weight_a.seqr);
    @(posedge vif.clk iff probe_if.wgt_buf_tile_ready);

    // ---- Step 4 : Enable + Start ----
    $display("                Step 4 : Enable + Start                 ");
    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0003;
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);
    @(posedge vif.clk iff probe_if.state === S_STREAM);

    // ---- Step 5 : Stream 8 activations with a 4‑cycle TVALID=0 gap after vector 3 ----
    $display("                Step 5 : Stream 8 activations with 4‑cycle TVALID=0 gap after vector 3                ");
    begin
      virtual accel_axis_activation_if act_vif = env.act_a.drv.vif;
      for (int v = 0; v < 8; v++) begin
        // Insert gap: after vector 3, hold TVALID=0 for 4 cycles
        if (v == 3) begin
          @(posedge act_vif.clk);
          act_vif.drv_cp.tvalid <= 0;
          $display("    Inserting 4‑cycle TVALID=0 bubble after vector 3");
          repeat(4) @(posedge act_vif.clk);
          $display("    Resuming TVALID after 4‑cycle bubble");
        end

        // Stream 2 beats (dense mode)
        for (int b = 0; b < 2; b++) begin
          @(posedge act_vif.clk);
          act_vif.drv_cp.tdata  <= {96'b0, 8'd3, 8'd3, 8'd3, 8'd3}; // a3..a0=3
          act_vif.drv_cp.tkeep  <= 16'hFFFF;
          act_vif.drv_cp.tlast  <= (v == 7) && (b == 1);
          act_vif.drv_cp.tvalid <= 1;
          // Wait for DUT to accept beat
          @(posedge act_vif.clk iff act_vif.mon_cp.tready);
        end
      end
      act_vif.drv_cp.tvalid <= 0;
    end

    // ---- Step 6 : Wait for done ----
    $display("                Step 6 : Wait for computation done                 ");
    @(posedge vif.clk iff probe_if.done === 1'b1);
    repeat(10) @(posedge vif.clk);

    $display("===================================================Test_047 : End of the test=================================================================");
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass

`endif