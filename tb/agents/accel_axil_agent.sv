`ifndef ACCEL_AXIL_AGENT_SV
`define ACCEL_AXIL_AGENT_SV


class axil_csr_drv extends uvm_driver #(axil_csr_tnx);
  
  `uvm_component_utils(axil_csr_drv)
  
  virtual accel_axil_if vif;
  axil_csr_tnx t;
  
  function new(string inst = "axil_csr_drv", uvm_component parent = null);
    
    super.new(inst,parent);
    
  endfunction
  
  
  virtual function void build_phase(uvm_phase phase);
    
    super.build_phase(phase);
    
    if(!uvm_config_db #(virtual accel_axil_if)::get(this,"","axil_if",vif))
      `uvm_fatal("axil_csr_drv","Unable to access config db");
    
  endfunction
  
  task do_reset();
    
    vif.drv_cp.awvalid <= 0;
    vif.drv_cp.wvalid  <= 0;
    vif.drv_cp.bready  <= 0;
    vif.drv_cp.arvalid <= 0;
    vif.drv_cp.rready  <= 0;
    vif.drv_cp.awaddr  <= 0;
    vif.drv_cp.awprot  <= 0;
    vif.drv_cp.wdata   <= 0;
    vif.drv_cp.wstrb   <= 0;
    vif.drv_cp.araddr  <= 0;
    vif.drv_cp.arprot  <= 0;
    @(posedge vif.clk iff vif.rst_n === 1);
    `uvm_info("axil_csr_drv","DUT RESET COMPLETED",UVM_NONE);
    $display("=========================================================================================================================================");
    
  endtask
  
  
  task do_write();
    
    //channel 1 : Write address
    @(vif.drv_cp);
    vif.drv_cp.awaddr <= t.addr;
    vif.drv_cp.awprot <= 3'b000;
    vif.drv_cp.awvalid <= 1;
    //wait for awready high
    `uvm_info("axil_csr_drv", $sformatf("WRITE addr=0x%0h data=0x%0h",t.addr, t.wdata), UVM_MEDIUM)
    
    @(vif.drv_cp iff vif.drv_cp.awready);
    vif.drv_cp.awvalid <= 0;
    `uvm_info("AXIL_DRV", "AW handshake done", UVM_HIGH)
    
    //channel 2 : Write data
    @(vif.drv_cp);
    vif.drv_cp.wdata <= t.wdata;
    vif.drv_cp.wstrb <= 4'hF;
    vif.drv_cp.wvalid <= 1;
    @(vif.drv_cp iff vif.drv_cp.wready);
    vif.drv_cp.wvalid <= 0;
    `uvm_info("axil_csr_drv","W handshake done",UVM_HIGH);
    
    //channel 3 : Write Response
    @(vif.drv_cp);
    vif.drv_cp.bready <= 1;
    @(vif.drv_cp iff vif.drv_cp.bvalid);
    t.resp = vif.drv_cp.bresp;
    vif.drv_cp.bready <= 0;
    `uvm_info("AXIL_DRV", $sformatf("B response=0x%0h", t.resp), UVM_HIGH)
      
    
  endtask
  
  
  task do_read();

    // Channel 1 — Read Address
    @(vif.drv_cp);
    vif.drv_cp.araddr  <= t.addr;
    vif.drv_cp.arprot  <= 3'b000;
    vif.drv_cp.arvalid <= 1;
    `uvm_info("AXIL_DRV", $sformatf("READ addr=0x%0h", t.addr), UVM_MEDIUM)

    @(vif.drv_cp iff vif.drv_cp.arready);
    vif.drv_cp.arvalid <= 0;
    `uvm_info("AXIL_DRV", "AR handshake done", UVM_HIGH)

    // Channel 2 — Read Data
    @(vif.drv_cp);
    vif.drv_cp.rready <= 1;

    @(vif.drv_cp iff vif.drv_cp.rvalid);
    t.rdata = vif.drv_cp.rdata;     // capture read data
    t.resp  = vif.drv_cp.rresp;     // capture read response
    vif.drv_cp.rready <= 0;
    `uvm_info("AXIL_DRV", $sformatf("R data=0x%0h resp=0x%0h",
              t.rdata, t.resp), UVM_HIGH)

 endtask
  
  virtual task run_phase(uvm_phase phase);
    
    //reset before start transaction
    do_reset();
    
    forever begin
      
      seq_item_port.get_next_item(t);
      
      if(t.we == 1)
        begin           
          do_write();
          `uvm_info("axil_csr_drv","[CSR] Write Data transaction completed",UVM_MEDIUM)         
        end
      else
        begin         
          do_read();
          `uvm_info("axil_csr_drv","[CSR] Read Data transaction completed",UVM_MEDIUM)
        end
             
      seq_item_port.item_done();
      
    end
    
  endtask
  
endclass


class axil_csr_mon extends uvm_monitor;

  `uvm_component_utils(axil_csr_mon)

  virtual accel_axil_if vif;
  axil_csr_tnx t;
  uvm_analysis_port #(axil_csr_tnx) send;
  

  function new(string inst = "axil_csr_mon",uvm_component parent = null);
    
    super.new(inst, parent);
    
  endfunction

  function void build_phase(uvm_phase phase);
    super.build_phase(phase);
    
    send = new("send", this);
    if(!uvm_config_db #(virtual accel_axil_if)::get(this, "", "axil_if", vif))
      `uvm_fatal("axil_csr_mon", "unable to access interface accel_axil_if")
      
  endfunction

  task run_phase(uvm_phase phase);
    forever begin

      // Fresh transaction object every iteration
      t = axil_csr_tnx::type_id::create("t");

      // Wait one clock edge
      @(vif.mon_cp);

      // Write completion
      if(vif.mon_cp.bvalid && vif.mon_cp.bready) begin
        t.addr  = vif.mon_cp.awaddr;
        t.wdata = vif.mon_cp.wdata;
        t.resp  = vif.mon_cp.bresp;
        t.we    = 1;
        send.write(t);
      end

      // Read completion
      else if(vif.mon_cp.rvalid && vif.mon_cp.rready) begin
        t.addr  = vif.mon_cp.araddr;
        t.rdata = vif.mon_cp.rdata;
        t.resp  = vif.mon_cp.rresp;
        t.we    = 0;
        send.write(t);
      end

    end
  endtask

endclass


class axil_csr_agent extends uvm_agent;

  `uvm_component_utils(axil_csr_agent)

  axil_csr_drv drv;
  axil_csr_mon mon;

  uvm_sequencer #(axil_csr_tnx) seqr;

  //forward monitor output through agent
  uvm_analysis_port #(axil_csr_tnx) aport;

  function new(string inst = "axil_csr_agent", uvm_component parent = null);

    super.new(inst,parent);

  endfunction


  virtual function void build_phase(uvm_phase phase);

    super.build_phase(phase);

    drv = axil_csr_drv::type_id::create("drv",this);
    mon = axil_csr_mon::type_id::create("mon",this);
    seqr = uvm_sequencer #(axil_csr_tnx)::type_id::create("seqr",this);
    aport = new("aport",this);

  endfunction


  virtual function void connect_phase(uvm_phase phase);

    super.connect_phase(phase);

    drv.seq_item_port.connect(seqr.seq_item_export);

    //forward monitor output through agent
    mon.send.connect(aport);

  endfunction

endclass


`endif