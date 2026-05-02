`ifndef TEST_070_CONSTRAINED_RANDOM_ALL_MODES_SV
`define TEST_070_CONSTRAINED_RANDOM_ALL_MODES_SV

class test_070_constrained_random_all_modes extends base_test;
  `uvm_component_utils(test_070_constrained_random_all_modes)

  rand bit [1:0]  rand_sparsity;
  rand int         rand_vcount;
  rand bit [7:0]  rand_w;
  rand bit [7:0]  rand_a;
  rand bit [1:0]  rand_idx0;
  rand bit [1:0]  rand_idx1;

  constraint c_vcount  { rand_vcount inside {[1:8]}; }      // smaller range
  constraint c_idx_neq { rand_idx1 != rand_idx0; }
  constraint c_1_4_w1  { rand_sparsity == 2'b10 -> rand_w == 0; }

  function new(string name = "test_070_constrained_random_all_modes", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    bit [31:0] sparsity_cfg;
    int total_checks = 0;
    localparam int SEEDS = 5;   // ← short run

    phase.raise_objection(this);

    $display("===================================================Test_070 : Constrained Random All Modes (%0d Seeds) - Start=================================================================", SEEDS);

    wr_seq = accel_csr_write_seq::type_id::create("wr_seq");
    w_tile_seq = accel_weight_tile_seq::type_id::create("w_tile_seq");
    a_stream_seq = accel_act_stream_seq::type_id::create("a_stream_seq");
    env.sco.flush_queues();

    // One-time soft reset
    $display("                Step 1 : Soft Reset + Clear                 ");
    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0048;
    wr_seq.start(env.axil_a.seqr);
    repeat(10) @(posedge vif.clk);
    
    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0008;
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);

    for (int s = 0; s < SEEDS; s++) begin
      if (!this.randomize()) begin
        `uvm_error(get_name(), "Randomization failed")
        break;
      end

      case (rand_sparsity)
        2'b00: sparsity_cfg = 32'h0000_0001;
        2'b01: sparsity_cfg = 32'h0000_0002;
        2'b10: sparsity_cfg = 32'h0000_0004;
        2'b11: sparsity_cfg = 32'h0000_0006;
      endcase

      // Each seed runs with its own CSR config
      wr_seq.csr_addr = CSR_CTRL;  
      wr_seq.csr_data = 32'h0000_0048;
      wr_seq.start(env.axil_a.seqr);
      
      wr_seq.csr_addr = CSR_CTRL;       
      wr_seq.csr_data = 32'h0000_0008; 
      wr_seq.start(env.axil_a.seqr);
      
      wr_seq.csr_addr = CSR_TILE_CFG;  
      wr_seq.csr_data = {16'd1, 16'(rand_vcount)};
      wr_seq.start(env.axil_a.seqr);
      
      wr_seq.csr_addr = CSR_ACT_TILE_CFG;
      wr_seq.csr_data = 32'h0001_0000;
      wr_seq.start(env.axil_a.seqr);
      
      wr_seq.csr_addr = CSR_SPARSITY; 
      wr_seq.csr_data = sparsity_cfg;
      wr_seq.start(env.axil_a.seqr);
      
      wr_seq.csr_addr = CSR_CTRL;    
      wr_seq.csr_data = 32'h0000_0001;
      wr_seq.start(env.axil_a.seqr);
      repeat(5) @(posedge vif.clk);

      // Build weight tile
      w_tile_tnx = axis_weight_tnx::type_id::create($sformatf("w_%0d", s));
      w_tile_tnx.sparsity_mode = sparsity_mode_e'(rand_sparsity);
      w_tile_tnx.sparse_mask   = 4'hF;
      foreach (w_tile_tnx.w0[i]) begin
        w_tile_tnx.w0[i]  = rand_w;
        w_tile_tnx.w1[i]  = (rand_sparsity == 2'b10) ? 8'h00 : rand_w;
        w_tile_tnx.idx0[i] = rand_idx0;
        w_tile_tnx.idx1[i] = rand_idx1;
      end
      w_tile_seq.t = w_tile_tnx;
      w_tile_seq.start(env.weight_a.seqr);
      @(posedge vif.clk iff probe_if.wgt_buf_tile_ready);

      wr_seq.csr_addr = CSR_CTRL;
      wr_seq.csr_data = 32'h0000_0003;
      wr_seq.start(env.axil_a.seqr);
      repeat(3) @(posedge vif.clk);
      @(posedge vif.clk iff probe_if.state === S_STREAM);

      // Stream activations
      for (int v = 0; v < rand_vcount; v++) begin
        a_stream_tnx = axis_act_tnx::type_id::create($sformatf("a_%0d_%0d", s, v));
        a_stream_tnx.a0 = rand_a;
        a_stream_tnx.a1 = rand_a;
        a_stream_tnx.a2 = rand_a;
        a_stream_tnx.a3 = rand_a;
        a_stream_tnx.is_last    = (v == rand_vcount - 1);
        a_stream_tnx.mode_dense = (rand_sparsity == 2'b00);
        a_stream_seq.t = a_stream_tnx;
        a_stream_seq.start(env.act_a.seqr);
      end

      total_checks += rand_vcount * TB_COLS;
      @(posedge vif.clk iff probe_if.done === 1'b1);
      repeat(3) @(posedge vif.clk);

      $display("    Seed %0d/%0d: mode=%0b vecs=%0d w=%0d a=%0d", s, SEEDS, rand_sparsity, rand_vcount, rand_w, rand_a);
    end

    $display("                Total scoreboard checks = %0d", total_checks);
    $display("===================================================Test_070 : End of the test=================================================================");
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass

`endif