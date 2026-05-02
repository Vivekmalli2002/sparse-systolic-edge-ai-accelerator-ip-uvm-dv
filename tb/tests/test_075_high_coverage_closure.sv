`ifndef TEST_075_HIGH_COVERAGE_CLOSURE_SV
`define TEST_075_HIGH_COVERAGE_CLOSURE_SV

class test_075_high_coverage_closure extends base_test;
  `uvm_component_utils(test_075_high_coverage_closure)

  function new(string name = "test_075_high_coverage_closure", uvm_component parent = null);
    super.new(name, parent);
  endfunction
  
  axis_act_tnx            a_vec;

  virtual task run_phase(uvm_phase phase);
    // Increased to 20: 16 directed weight crosses + 4 random sweeps
    int                     num_seeds = 17;          
    int                     vectors_per_seed;
    int                     seed;
    logic [31:0]            sparsity_cfg_val;
    sparsity_mode_e         mode;
    int                     mask_sel;
    int                     pattern;
    real                    cov_axil, cov_weight, cov_act, cov_result, cov_fsm, avg_cov;
    
    // The exact 4 modes and 4 masks needed to fill the cross_sparsity_mask bins
    sparsity_mode_e modes[] = {SPARSITY_DENSE, SPARSITY_2_4, SPARSITY_1_4, SPARSITY_4_8};
    logic [3:0] target_masks[] = {4'b0000, 4'b1111, 4'b1010, 4'b0101};
    
    phase.raise_objection(this);

    $display("============================Test_075 : High Coverage Sweep (Completing) Start============================================================");

    wr_seq       = accel_csr_write_seq::type_id::create("wr_seq");
    rd_seq       = accel_csr_read_seq::type_id::create("rd_seq");
    w_tile_seq   = accel_weight_tile_seq::type_id::create("w_tile_seq");
    a_stream_seq = accel_act_stream_seq::type_id::create("a_stream_seq");
    w_tile_tnx = axis_weight_tnx::type_id::create("w_tile_tnx");

    env.sco.flush_queues();

    $display("                Step 1 : Global Soft Reset + Clear                 ");
    wr_seq.csr_addr = CSR_CTRL; 
    wr_seq.csr_data = 32'h0000_0048; 
    wr_seq.start(env.axil_a.seqr);   
    repeat(10) @(posedge vif.clk);
    
    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0008;
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);

    for (seed = 0; seed < num_seeds; seed++) begin

      // Seeds 0-15: Directed Weight Coverage (4 modes x 4 masks)
      if (seed < 16) begin
        mode = modes[seed / 4];
        mask_sel = seed % 4;
        vectors_per_seed = 2; 
      end else begin
        // Seeds 16-19: Random mode & Activations
        randcase
          25: mode = SPARSITY_DENSE;
          25: mode = SPARSITY_2_4;
          25: mode = SPARSITY_1_4;
          25: mode = SPARSITY_4_8;
        endcase
        mask_sel = $urandom_range(0,3);
        vectors_per_seed = $urandom_range(1, 2);
      end

      // CSR writes/reads
      wr_seq.csr_addr = CSR_IRQ_EN;
      wr_seq.csr_data = (seed % 2 == 0) ? 32'h0000_0001 : 32'h0000_0000;
      wr_seq.start(env.axil_a.seqr);
      rd_seq.csr_addr = CSR_IRQ_EN;
      rd_seq.start(env.axil_a.seqr);

      wr_seq.csr_addr = CSR_CTRL;
      wr_seq.csr_data = 32'h0000_0001;
      wr_seq.start(env.axil_a.seqr);
      rd_seq.csr_addr = CSR_CTRL;
      rd_seq.start(env.axil_a.seqr);

      rd_seq.csr_addr = CSR_STATUS;
      rd_seq.start(env.axil_a.seqr);

      // Configure DUT Sparsity
      case (mode)
        SPARSITY_DENSE: sparsity_cfg_val = 32'h0000_0001;
        SPARSITY_2_4  : sparsity_cfg_val = 32'h0000_0002;
        SPARSITY_1_4  : sparsity_cfg_val = 32'h0000_0004;
        SPARSITY_4_8  : sparsity_cfg_val = 32'h0000_0008;
        default:        sparsity_cfg_val = 32'h0000_0001;
      endcase

      wr_seq.csr_addr = CSR_SPARSITY;   
      wr_seq.csr_data = sparsity_cfg_val;          
      wr_seq.start(env.axil_a.seqr);
      
      wr_seq.csr_addr = CSR_TILE_CFG;  
      wr_seq.csr_data = {16'd1, 16'(vectors_per_seed)};
      wr_seq.start(env.axil_a.seqr);
      
      wr_seq.csr_addr = CSR_ACT_TILE_CFG;
      wr_seq.csr_data = 32'h0001_0000;      
      wr_seq.start(env.axil_a.seqr);

      
      if (!w_tile_tnx.randomize() with { sparsity_mode == mode; }) begin
        `uvm_error("TEST", "Weight tile randomization failed")
        continue;
      end

      // --- PROCEDURAL OVERRIDES TO HIT WEIGHT COVERAGE WITHOUT SOLVER CLASHES ---
      w_tile_tnx.sparse_mask = target_masks[mask_sel];

      for (int i = 0; i < TB_ROWS * TB_COLS; i++) begin
        if (seed < 16) begin
          // Toggle w0 and w1 to zero to hit cp_w0_zero and cp_w1_zero
          w_tile_tnx.w0[i] = ((seed % 2) == 0) ? 8'sd0 : 8'sd5;
          // Respect SPARSITY_1_4 hardware rule to prevent mismatches
          w_tile_tnx.w1[i] = (mode == SPARSITY_1_4) ? 8'sd0 : (((seed % 2) == 0) ? 8'sd0 : 8'sd5);
        end
        
        // Assign indices, ensuring idx0[0] toggles between High (3) and Low (1)
        case (i % 4)
          0: begin w_tile_tnx.idx0[i] = (seed % 2 == 0) ? 2'b11 : 2'b01; w_tile_tnx.idx1[i] = 2'b10; end
          1: begin w_tile_tnx.idx0[i] = 2'b01; w_tile_tnx.idx1[i] = 2'b10; end
          2: begin w_tile_tnx.idx0[i] = 2'b10; w_tile_tnx.idx1[i] = 2'b11; end
          3: begin w_tile_tnx.idx0[i] = 2'b11; w_tile_tnx.idx1[i] = 2'b00; end
        endcase
      end

      w_tile_seq.t = w_tile_tnx;
      w_tile_seq.start(env.weight_a.seqr);
      @(posedge vif.clk iff probe_if.wgt_buf_tile_ready);

      wr_seq.csr_addr = CSR_CTRL; 
      wr_seq.csr_data = 32'h0000_0003; 
      wr_seq.start(env.axil_a.seqr);
      repeat(5) @(posedge vif.clk);
      
      @(posedge vif.clk iff probe_if.state === S_STREAM);

      // Stream Activations
      for (int v = 0; v < vectors_per_seed; v++) begin
        
        a_vec = axis_act_tnx::type_id::create("a_vec");
        
        pattern = $urandom_range(0,4);
        
        case (pattern)
          
          0: begin a_vec.a0 = 0; a_vec.a1 = 0; a_vec.a2 = 0; a_vec.a3 = 0; end
          1: begin a_vec.a0 = -8'sd10; a_vec.a1 = 8'sd10; a_vec.a2 = -8'sd5; a_vec.a3 = 8'sd5; end
          2: begin a_vec.a0 = 8'sd7; a_vec.a1 = 0; a_vec.a2 = 0; a_vec.a3 = 0; end
          3: begin a_vec.a0 = -8'sd3; a_vec.a1 = -8'sd3; a_vec.a2 = -8'sd3; a_vec.a3 = -8'sd3; end
          
          default: begin
            a_vec.a0 = $urandom_range(1,127); a_vec.a1 = $urandom_range(1,127);
            a_vec.a2 = $urandom_range(1,127); a_vec.a3 = $urandom_range(1,127);
          end
          
        endcase
        
        a_vec.is_last   = (v == vectors_per_seed - 1);
        a_vec.mode_dense = (mode == SPARSITY_DENSE) ? 1 : 0;
        a_stream_seq.t  = a_vec;
        a_stream_seq.start(env.act_a.seqr);
        
      end

      @(posedge vif.clk iff probe_if.done === 1'b1);
      repeat(2) @(posedge vif.clk);  // minimal wait

      // Light touch of perf reads
      rd_seq.csr_addr = CSR_PERF_CYCLES;
      rd_seq.start(env.axil_a.seqr);
      
      rd_seq.csr_addr = CSR_PERF_MAC;   
      rd_seq.start(env.axil_a.seqr);

      cov_axil   = env.cov_sub.cg_axil.get_coverage();
      cov_weight = env.cov_sub.cg_weight.get_coverage();
      cov_act    = env.cov_sub.cg_activation.get_coverage();
      cov_result = env.cov_sub.cg_result.get_coverage();
      cov_fsm    = env.cov_sub.cg_fsm.get_coverage();
      avg_cov    = (cov_axil + cov_weight + cov_act + cov_result + cov_fsm) / 5.0;

      $display("Seed %0d/%0d – Coverage: AXL=%.1f%% WGT=%.1f%% ACT=%.1f%% RES=%.1f%% FSM=%.1f%% => AVG=%.1f%%",
               seed, num_seeds-1, cov_axil, cov_weight, cov_act, cov_result, cov_fsm, avg_cov);

      env.sco.flush_queues();
    end
    
    // --- AXIL PUNCHER: Hit the illegal address (SLVERR) reading and writing ---
    $display("                Step 2 : AXIL Error Coverage                 ");
    wr_seq.csr_addr = 12'hFFF; 
    wr_seq.csr_data = 32'hDEADBEEF;
    wr_seq.start(env.axil_a.seqr);
    
    rd_seq.csr_addr = 12'hFFF;
    rd_seq.start(env.axil_a.seqr);

    $display("===================================================Test_075 : End of the test=================================================================");
    `uvm_info("COVERAGE", $sformatf("Final Coverage = %0.2f%%", avg_cov), UVM_NONE)
    phase.drop_objection(this);
  endtask

endclass

`endif