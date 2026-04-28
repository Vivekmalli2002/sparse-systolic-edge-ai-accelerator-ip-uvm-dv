`ifndef ACCEL_SEQUENCES_SV
`define ACCEL_SEQUENCES_SV


class accel_csr_write_seq extends uvm_sequence #(axil_csr_tnx);

    `uvm_object_utils(accel_csr_write_seq)

    // Test sets these before calling start()
    logic [11:0] csr_addr;
    logic [31:0] csr_data;
  
    axil_csr_tnx t;

    function new(string name = "accel_csr_write_seq");
      
        super.new(name);
      
    endfunction

    virtual task body();
        t = axil_csr_tnx::type_id::create("t");

        start_item(t);
        // Set directed fields — addr and we are not rand
        t.addr  = csr_addr;
        t.wdata = csr_data;
        t.we    = 1;
        finish_item(t);

        `uvm_info("CSR_WRITE_SEQ",$sformatf("Written addr=0x%0h data=0x%0h",t.addr, t.wdata), UVM_MEDIUM)
    endtask

endclass


class accel_csr_read_seq extends uvm_sequence #(axil_csr_tnx);

  `uvm_object_utils(accel_csr_read_seq)

  // Test sets these before calling start()
  logic [11:0] csr_addr;
  logic [31:0] csr_rdata;
  
  axil_csr_tnx t;

  function new(string name = "accel_csr_read_seq");
    
        super.new(name);
    
  endfunction
  

  virtual task body();
      t = axil_csr_tnx::type_id::create("t");
    
      start_item(t);
    
      t.addr = csr_addr;
      t.we   = 0;
    
      finish_item(t);
    
      csr_rdata = t.rdata;
  endtask

endclass



class accel_weight_tile_seq extends uvm_sequence #(axis_weight_tnx);
  
  `uvm_object_utils(accel_weight_tile_seq)
  
  axis_weight_tnx t;
  
  
  function new(string inst = "accel_weight_tile_seq");
    
    super.new(inst);
    
  endfunction
  
  
  virtual task body();
    
    start_item(t);
    finish_item(t);
    `uvm_info("WEIGHT_TILE_SEQ", "Weight tile streamed", UVM_MEDIUM)
    
  endtask
  
  
endclass



class accel_act_stream_seq extends uvm_sequence #(axis_act_tnx);
  
  `uvm_object_utils(accel_act_stream_seq)
  
  axis_act_tnx t;
  
  function new(string inst = "accel_act_stream_seq");
    
    super.new(inst);
    
  endfunction
  
  
  virtual task body();
    
    start_item(t);
    finish_item(t);
    `uvm_info("ACT_STREAM_SEQ", "Activation vector streamed", UVM_MEDIUM)
    
  endtask
  
endclass


`endif