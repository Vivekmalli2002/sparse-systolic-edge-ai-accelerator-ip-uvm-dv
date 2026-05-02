`ifndef TEST_013_DENSE_MAX_WEIGHTS_SV
`define TEST_013_DENSE_MAX_WEIGHTS_SV


class test_013_dense_max_weights extends base_test;

  `uvm_component_utils(test_013_dense_max_weights)
  
  function new(string inst = "test_013_dense_max_weights", uvm_component parent = null);
  
    super.new(inst,parent);
  
  endfunction
  
  
  virtual task run_phase(uvm_phase phase);
  
    phase.raise_objection(this);


    w_tile_seq = accel_weight_tile_seq::type_id::create("w_tile_seq");
    a_stream_seq = accel_act_stream_seq::type_id::create("a_stream_seq");
    w_tile_tnx = axis_weight_tnx::type_id::create("w_tile_tnx");
    a_stream_tnx = axis_act_tnx::type_id::create("a_stream_tnx");

    env.sco.flush_queues();
    
    //weight tile
    for(int i = 0; i < TB_ROWS * TB_COLS; i++) begin
      
      w_tile_tnx.w0[i] = 8'sd127;
      w_tile_tnx.w1[i] = 8'sd127;
      w_tile_tnx.idx0[i] = 0;
      w_tile_tnx.idx1[i] = 1;
      
    end
    
    w_tile_tnx.sparsity_mode = SPARSITY_DENSE;
    w_tile_tnx.sparse_mask = 4'hF;
    
    //Activation
    a_stream_tnx.a0 = 8'sd1;
    a_stream_tnx.a1 = 8'sd1;
    a_stream_tnx.a2 = 8'sd1;
    a_stream_tnx.a3 = 8'sd1;
    a_stream_tnx.mode_dense = 1;
    
    //call the run_compute_test
    $display("===================================================Test_013 : Dense Max Weight - Start=================================================================");
    
    run_compute_test(w_tile_tnx, a_stream_tnx, 32'h0000_0001, 1, "Test_013 : Dense Max Weight");
    
    $display("===================================================Test_013 : End of the test=================================================================");
    
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)

    phase.drop_objection(this);
  
  endtask


endclass



`endif