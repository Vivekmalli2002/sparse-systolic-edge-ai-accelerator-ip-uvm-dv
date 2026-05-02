`ifndef TEST_064_WEIGHT_TILE_REUSE_SV
`define TEST_064_WEIGHT_TILE_REUSE_SV

class test_064_weight_tile_reuse extends base_test;
  `uvm_component_utils(test_064_weight_tile_reuse)

  function new(string name = "test_064_weight_tile_reuse", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  // Helper task – declares at class level (not inside another task)
  task automatic stream_8_vectors(int a_val);
    axis_act_tnx  act;
    for (int v = 0; v < 8; v++) begin
      act = axis_act_tnx::type_id::create($sformatf("act_tile%0d_vec%0d", a_val, v));
      act.a0 = a_val; act.a1 = a_val;
      act.a2 = a_val; act.a3 = a_val;
      act.is_last    = 1'b0;
      act.mode_dense = 1'b1;
      // no sparsity_mode here – that belongs to weight transaction
      a_stream_seq.t = act;
      a_stream_seq.start(env.act_a.seqr);
    end
  endtask

  virtual task run_phase(uvm_phase phase);
    phase.raise_objection(this);

    $display("===================================================Test_064 : Weight Tile Reuse Without Reload - Start=================================================================");

    w_tile_seq   = accel_weight_tile_seq::type_id::create("w_tile_seq");
    a_stream_seq = accel_act_stream_seq::type_id::create("a_stream_seq");
    w_tile_tnx   = axis_weight_tnx::type_id::create("w_tile_tnx");
    wr_seq       = accel_csr_write_seq::type_id::create("wr_seq");

    env.sco.flush_queues();

    // Build weight tile (all ones)
    for (int i = 0; i < TB_ROWS * TB_COLS; i++) begin
      w_tile_tnx.w0[i] = 1;  w_tile_tnx.w1[i] = 1;
      w_tile_tnx.idx0[i] = 0; w_tile_tnx.idx1[i] = 1;
    end
    w_tile_tnx.sparsity_mode = SPARSITY_DENSE;
    w_tile_tnx.sparse_mask   = 4'hF;

    // Step 1 : Reset
    $display("                Step 1 : Soft Reset + Clear                ");
    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0048;
    wr_seq.start(env.axil_a.seqr);
    repeat(10) @(posedge vif.clk);
    
    wr_seq.csr_addr = CSR_CTRL; 
    wr_seq.csr_data = 32'h0000_0008;
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);

    // Step 2 : Configure: 1 weight tile, 8 vectors/tile, act_tile_count=3
    $display("                Step 2 : Configure tile_count=1, vector_count=8, act_tile_count=3                ");
    wr_seq.csr_addr = CSR_TILE_CFG;   
    wr_seq.csr_data = 32'h0001_0008; 
    wr_seq.start(env.axil_a.seqr);
    
    wr_seq.csr_addr = CSR_ACT_TILE_CFG;
    wr_seq.csr_data = 32'h0003_0000;
    wr_seq.start(env.axil_a.seqr);
    
    wr_seq.csr_addr = CSR_SPARSITY;  
    wr_seq.csr_data = 32'h0000_0001; 
    wr_seq.start(env.axil_a.seqr);
    wr_seq.csr_addr = CSR_CTRL;       
    wr_seq.csr_data = 32'h0000_0001;
    wr_seq.start(env.axil_a.seqr);

    // Step 3 : Stream weight tile ONCE
    $display("                Step 3 : Stream weight tile once (all-ones).                ");
    w_tile_seq.t = w_tile_tnx;
    w_tile_seq.start(env.weight_a.seqr);

    // Enable + Start
    wr_seq.csr_addr = CSR_CTRL;
    wr_seq.csr_data = 32'h0000_0003;
    wr_seq.start(env.axil_a.seqr);
    repeat(5) @(posedge vif.clk);
    
    @(posedge vif.clk iff probe_if.state === S_STREAM);

    // Tell scoreboard to expect 8*3 = 24 result vectors before popping weight
    env.sco.set_expected_results_per_weight(24);

    // Tile 1: a=1
    $display("                Tile 1 (a=1)                ");
    stream_8_vectors(1);

    // Tile 2: a=2
    $display("                Tile 2 (a=2)                ");
    stream_8_vectors(2);

    // Tile 3: a=3
    $display("                Tile 3 (a=3)                ");
    stream_8_vectors(3);

    // Wait for done
    $display("                Waiting for computation done...                ");
    @(posedge vif.clk iff probe_if.done === 1'b1);
    repeat(10) @(posedge vif.clk);

    $display("===================================================Test_064 : End of the test=================================================================");
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass

`endif