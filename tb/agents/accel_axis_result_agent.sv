`ifndef ACCEL_AXIS_RESULT_AGENT_SV
`define ACCEL_AXIS_RESULT_AGENT_SV


class axis_result_mon extends uvm_monitor;
  
  `uvm_component_utils(axis_result_mon)
  
  uvm_analysis_port #(axis_result_tnx) send;
  axis_result_tnx t;
  virtual accel_axis_result_if vif;
  
  function new(string inst = "axis_result_mon", uvm_component parent = null);
    
    super.new(inst,parent);
    
  endfunction
  
  
  virtual function void build_phase(uvm_phase phase);
    
    super.build_phase(phase);
    
    send = new("send",this);
    if(!uvm_config_db #(virtual accel_axis_result_if)::get(this,"","result_if",vif))
      `uvm_fatal("axis_result_if","Unable to access interface accel_axis_result_if")
    
  endfunction
      
      
  task run_phase(uvm_phase phase);

    int beats_per_vector;
    int col;

    // Always accept results — drive tready=1
    vif.drv_cp.tready <= 1;

    beats_per_vector = (TB_COLS + 3) / 4;  // ceil(8/4) = 2

    forever begin

        // Fresh transaction for each result vector
        t = axis_result_tnx::type_id::create("t");

        // Collect all beats for one result vector
        for(int beat = 0; beat < beats_per_vector; beat++) begin

            // Wait for valid handshake
            @(vif.mon_cp);
            while(!(vif.mon_cp.tvalid && vif.mon_cp.tready))
                @(vif.mon_cp);

            // Unpack 4 results from this beat
            for(int r = 0; r < 4; r++) begin
                col = beat * 4 + r;
                if(col < TB_COLS) begin
                    t.result[col] = vif.mon_cp.tdata[r*32 +: 32];
                end
            end

            // Capture is_last on final beat
            if(beat == beats_per_vector-1)
                t.is_last = vif.mon_cp.tlast;

        end

        // Complete vector captured — send to scoreboard
        `uvm_info("RESULT_MON",$sformatf("Result vector captured — last=%0b", t.is_last),UVM_MEDIUM)
        send.write(t);

    end

  endtask
  
  
endclass


class axis_result_agent extends uvm_agent;

    `uvm_component_utils(axis_result_agent)

    axis_result_mon mon;
    uvm_analysis_port #(axis_result_tnx) aport;

    // No drv — DUT produces results
    // No seqr — no sequences needed

    function new(string name = "axis_result_agent",uvm_component parent = null);
      
        super.new(name, parent);
      
    endfunction

    function void build_phase(uvm_phase phase);
      
        super.build_phase(phase);
      
        aport = new("aport", this);
        mon   = axis_result_mon::type_id::create("mon", this);
      
    endfunction

    function void connect_phase(uvm_phase phase);
      
        super.connect_phase(phase);
      
        mon.send.connect(aport);
      
    endfunction

endclass


`endif