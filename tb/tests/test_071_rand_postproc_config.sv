`ifndef TEST_071_RAND_POSTPROC_CONFIG_SV
`define TEST_071_RAND_POSTPROC_CONFIG_SV

class test_071_rand_postproc_config extends base_test;
  `uvm_component_utils(test_071_rand_postproc_config)

  rand bit [2:0]  rand_op_sel;
  rand bit [15:0] rand_bias;
  rand bit [15:0] rand_scale;
  rand bit [4:0]  rand_shift;
  rand bit        rand_round_en;
  rand bit        rand_sat_en;
  rand bit [31:0] rand_sat_max;
  rand bit [31:0] rand_sat_min;
  rand bit [2:0]  rand_act_fn;

  constraint c_op   { rand_op_sel inside {[0:4]}; }
  constraint c_scl  { rand_scale  inside {[1:255]}; }
  constraint c_shft { rand_shift  inside {[0:15]}; }
  constraint c_sat  { signed'(rand_sat_max) > signed'(rand_sat_min); }
  constraint c_fn   { rand_act_fn inside {3'b000,3'b001,3'b011}; }

  function new(string name = "test_071_rand_postproc_config", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    localparam int SEEDS = 10;
    phase.raise_objection(this);

    $display("===================================================Test_071 : Constrained Random Post-Proc Config (%0d Seeds) - Start=================================================================", SEEDS);

    wr_seq       = accel_csr_write_seq::type_id::create("wr_seq");
    w_tile_seq   = accel_weight_tile_seq::type_id::create("w_tile_seq");
    a_stream_seq = accel_act_stream_seq::type_id::create("a_stream_seq");
    env.sco.flush_queues();

    for (int s = 0; s < SEEDS; s++) begin
      if (!this.randomize()) begin
        `uvm_error(get_name(), "PP randomisation failed")
        break;
      end

      // Soft reset
      wr_seq.csr_addr = CSR_CTRL;
      wr_seq.csr_data = 32'h0000_0048; 
      wr_seq.start(env.axil_a.seqr);
      repeat(10) @(posedge vif.clk);
      
      wr_seq.csr_addr = CSR_CTRL; 
      wr_seq.csr_data = 32'h0000_0008;
      wr_seq.start(env.axil_a.seqr);
      repeat(5) @(posedge vif.clk);

      // Post‑processing config
      wr_seq.csr_addr = CSR_PP_CTRL; 
      wr_seq.csr_data = {22'b0, rand_sat_en, rand_round_en, 5'b0, rand_op_sel};
      wr_seq.start(env.axil_a.seqr);
      
      wr_seq.csr_addr = CSR_PP_SCALE; 
      wr_seq.csr_data = {16'b0, rand_scale};
      wr_seq.start(env.axil_a.seqr);
      
      wr_seq.csr_addr = CSR_PP_SHIFT; 
      wr_seq.csr_data = {27'b0, rand_shift};
      wr_seq.start(env.axil_a.seqr);
      
      if (rand_sat_en) begin
        wr_seq.csr_addr = CSR_PP_SAT_MAX;
        wr_seq.csr_data = rand_sat_max; 
        wr_seq.start(env.axil_a.seqr);
        
        wr_seq.csr_addr = CSR_PP_SAT_MIN;
        wr_seq.csr_data = rand_sat_min; 
        wr_seq.start(env.axil_a.seqr);
      end
      wr_seq.csr_addr = CSR_ACT_CFG; 
      wr_seq.csr_data = {29'b0, rand_act_fn};
      wr_seq.start(env.axil_a.seqr);
      
      if (rand_op_sel inside {3'b001,3'b100}) begin
        wr_seq.csr_addr = CSR_PP_BIAS_ADDR; 
        wr_seq.csr_data = 32'h0;
        wr_seq.start(env.axil_a.seqr);
        for (int c = 0; c < TB_COLS; c++) begin
          wr_seq.csr_addr = CSR_PP_BIAS_DATA;
          wr_seq.csr_data = {16'b0, rand_bias};
          wr_seq.start(env.axil_a.seqr);
        end
      end

      // Fixed compute: 1 vector, all-ones weights, dense
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
      repeat(3) @(posedge vif.clk);

      // Build all-ones weight tile
      w_tile_tnx = axis_weight_tnx::type_id::create($sformatf("w_%0d", s));
      w_tile_tnx.sparsity_mode = SPARSITY_DENSE;
      w_tile_tnx.sparse_mask   = 4'hF;
      foreach (w_tile_tnx.w0[i]) begin
        w_tile_tnx.w0[i] = 1; w_tile_tnx.w1[i] = 1;
        w_tile_tnx.idx0[i] = 0; w_tile_tnx.idx1[i] = 1;
      end
      w_tile_seq.t = w_tile_tnx;
      w_tile_seq.start(env.weight_a.seqr);
      @(posedge vif.clk iff probe_if.wgt_buf_tile_ready);

      wr_seq.csr_addr = CSR_CTRL; 
      wr_seq.csr_data = 32'h0000_0003;
      wr_seq.start(env.axil_a.seqr);
      repeat(3) @(posedge vif.clk);
      @(posedge vif.clk iff probe_if.state === S_STREAM);

      // Single activation vector
      a_stream_tnx = axis_act_tnx::type_id::create($sformatf("a_%0d", s));
      a_stream_tnx.a0 = 1; a_stream_tnx.a1 = 1;
      a_stream_tnx.a2 = 1; a_stream_tnx.a3 = 1;
      a_stream_tnx.is_last    = 1'b1;
      a_stream_tnx.mode_dense = 1'b1;
      a_stream_seq.t = a_stream_tnx;
      a_stream_seq.start(env.act_a.seqr);

      @(posedge vif.clk iff probe_if.done === 1'b1);
      repeat(3) @(posedge vif.clk);

      if (s % 2 == 0)
        $display("    Seed %0d/%0d: op=%0d scl=%0d shft=%0d sat=%0b fn=%0d", s, SEEDS, rand_op_sel, rand_scale, rand_shift, rand_sat_en, rand_act_fn);
    end

    $display("===================================================Test_071 : End of the test=================================================================");
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass

`endif