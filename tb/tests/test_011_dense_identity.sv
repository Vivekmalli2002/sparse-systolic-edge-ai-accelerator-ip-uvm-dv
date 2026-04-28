`ifndef TEST_011_DENSE_IDENTITY_SV
`define TEST_011_DENSE_IDENTITY_SV


class test_011_dense_identity_weights extends functionality_basetest;

  `uvm_component_utils(test_011_dense_identity_weights)
  
  function new(string inst = "test_011_dense_identity", uvm_component parent = null);
  
    super.new(inst,parent);
  
  endfunction
  
  
  virtual task run_phase(uvm_phase phase);
  
    phase.raise_objection(this);


    w_tile_seq = accel_weight_tile_seq::type_id::create("w_tile_seq");
    a_stream_seq = accel_act_stream_seq::type_id::create("a_stream_seq");
    w_tile_tnx = axis_weight_tnx::type_id::create("w_tile_tnx");
    a_stream_tnx = axis_act_tnx::type_id::create("a_stream_tnx");

    env.sco.flush_queues();

    // Identity — only diagonal PEs have w0=1
    // w0[r*TB_COLS+r] = 1, all others = 0
    for(int i = 0; i < TB_ROWS*TB_COLS; i++) begin
        w_tile_tnx.w0[i] = 8'sd0;
        w_tile_tnx.w1[i] = 8'sd0;
        w_tile_tnx.idx0[i] = 2'd0;
        w_tile_tnx.idx1[i] = 2'd1;
    end
    // Diagonal only
    for(int r = 0; r < TB_ROWS; r++)
        w_tile_tnx.w0[r*TB_COLS+r] = 8'sd1;

    w_tile_tnx.sparsity_mode = SPARSITY_DENSE;
    w_tile_tnx.sparse_mask   = 4'hF;

    a_stream_tnx.a0 = 8'sd3; 
    a_stream_tnx.a1 = 8'sd3;
    a_stream_tnx.a2 = 8'sd3; 
    a_stream_tnx.a3 = 8'sd3;
    a_stream_tnx.mode_dense = 1;

    $display("===================================================Test_011 : Dense Identity Weights - Start=================================================================");
    
    run_compute_test(w_tile_tnx, a_stream_tnx, 32'h0000_0001, 1,"Test_011 : Dense Identity Weights");
    
    $display("===================================================Test_011 : End of the test=================================================================");

    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)

    phase.drop_objection(this);
  
  endtask


endclass



`endif