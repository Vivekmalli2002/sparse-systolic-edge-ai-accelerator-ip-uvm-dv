`ifndef ACCEL_AXIS_ACT_AGENT_SV
`define ACCEL_AXIS_ACT_AGENT_SV


class axis_act_drv extends uvm_driver #(axis_act_tnx);

    `uvm_component_utils(axis_act_drv)

    axis_act_tnx t;
    virtual accel_axis_activation_if vif;

    function new(string name = "axis_act_drv",uvm_component parent = null);
      
        super.new(name, parent);
      
    endfunction

    function void build_phase(uvm_phase phase);
      
        super.build_phase(phase);
      
        if(!uvm_config_db #(virtual accel_axis_activation_if)::get(this, "", "act_if", vif))
            `uvm_fatal("ACT_DRV","unable to access accel_axis_activation_if")
          
    endfunction

          
    task do_reset();
      
        vif.drv_cp.tdata  <= '0;
        vif.drv_cp.tkeep  <= '0;
        vif.drv_cp.tlast  <= 0;
        vif.drv_cp.tvalid <= 0;
        @(posedge vif.clk iff vif.rst_n);
        `uvm_info("ACT_DRV", "Reset done", UVM_MEDIUM)
       $display("=========================================================================================================================================");
      
    endtask
      

    task run_phase(uvm_phase phase);
      
        int max_beats;

        do_reset();

        forever begin
            seq_item_port.get_next_item(t);

            // Dense = 2 beats, Sparse = 1 beat
            max_beats = t.mode_dense ? 2 : 1;

            for(int beat = 0; beat < max_beats; beat++) begin

                @(vif.drv_cp);
                vif.drv_cp.tdata  <= {96'b0, t.a3, t.a2, t.a1, t.a0};
                vif.drv_cp.tkeep  <= 16'hFFFF;
                vif.drv_cp.tvalid <= 1;
         
                // tlast only on last beat of last vector
                vif.drv_cp.tlast  <= (beat == max_beats-1) && t.is_last;

                @(posedge vif.clk iff vif.drv_cp.tready);

                // Deassert only after last beat of last vector
                if((beat == max_beats-1) && t.is_last)
                    vif.drv_cp.tvalid <= 0;

                `uvm_info("ACT_DRV",$sformatf("Beat %0d/%0d sent mode=%0s last=%0b",beat+1, max_beats,t.mode_dense ?"DENSE":"SPARSE",t.is_last), UVM_MEDIUM)

            end

            seq_item_port.item_done();
        end

    endtask

endclass


class axis_act_mon extends uvm_monitor;

    `uvm_component_utils(axis_act_mon)

    uvm_analysis_port #(axis_act_tnx) send;
  
    virtual accel_axis_activation_if vif;
    virtual accel_dut_probes_if probe_if;
  
    axis_act_tnx t;
    int mode_dense;  // from config_db

    function new(string name = "axis_act_mon",uvm_component parent = null);
      
        super.new(name, parent);
      
    endfunction
  

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
      
        send = new("send", this);
        if(!uvm_config_db #(virtual accel_axis_activation_if)::get(this, "", "act_if", vif))
            `uvm_fatal("ACT_MON", "unable to access accel_axis_activation_if")

        // Get mode — default dense if not set
          if(!uvm_config_db #(virtual accel_dut_probes_if)::get(this, "", "probe_if", probe_if))
            `uvm_fatal("ACT_MON","unable to access the interface accel_dut_probes_if")
      
    endfunction
  

  task run_phase(uvm_phase phase);

        // Wait for reset first
        //@(posedge vif.clk iff vif.rst_n);

        forever begin
            t = axis_act_tnx::type_id::create("t");

            // Wait for beat 1 FIRST
            @(posedge vif.clk iff (vif.tvalid && vif.tready));

            // NOW read mode — DUT is actively streaming, mode is stable
            t.mode_dense = probe_if.mode_dense;

            t.a0      = vif.tdata[7:0];
            t.a1      = vif.tdata[15:8];
            t.a2      = vif.tdata[23:16];
            t.a3      = vif.tdata[31:24];
            t.is_last = vif.tlast;

            if(t.mode_dense) begin
                @(posedge vif.clk iff (vif.tvalid && vif.tready));
                t.is_last = vif.tlast;
            end

            send.write(t);
            `uvm_info("ACT_MON", $sformatf(
                "Vector captured a0=%0d a1=%0d a2=%0d a3=%0d last=%0b mode=%0s",
                t.a0, t.a1, t.a2, t.a3, t.is_last,
                t.mode_dense ? "DENSE" : "SPARSE"), UVM_MEDIUM)
        end
      
    endtask

endclass
      

class axis_act_agent extends uvm_agent;
  
  `uvm_component_utils(axis_act_agent)
  
  axis_act_drv drv;
  axis_act_mon mon;
  
  uvm_sequencer #(axis_act_tnx) seqr;
  uvm_analysis_port #(axis_act_tnx) aport;
  
  function new(string inst = "axis_act_agent", uvm_component parent = null);
    
    super.new(inst,parent);
    
  endfunction
  
  
  virtual function void build_phase(uvm_phase phase);
    
    super.build_phase(phase);
    
    aport = new("aport",this);
    drv = axis_act_drv::type_id::create("drv",this);
    mon = axis_act_mon::type_id::create("mon",this);
    seqr = uvm_sequencer #(axis_act_tnx)::type_id::create("seqr",this);
    
  endfunction
  

  virtual function void connect_phase(uvm_phase phase);
    
    super.connect_phase(phase);
    
    drv.seq_item_port.connect(seqr.seq_item_export);
    mon.send.connect(aport);  
    
  endfunction


endclass


`endif