`ifndef ACCEL_AXIS_WEIGHT_AGENT_SV
`define ACCEL_AXIS_WEIGHT_AGENT_SV


class axis_weight_drv extends uvm_driver #(axis_weight_tnx);

    `uvm_component_utils(axis_weight_drv)

    virtual accel_axis_weight_if vif;
    axis_weight_tnx              t;

    function new(string name = "axis_weight_drv",uvm_component parent = null);
      
        super.new(name, parent);
      
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
      
        if(!uvm_config_db #(virtual accel_axis_weight_if)::get(
            this, "", "weight_if", vif))
            `uvm_fatal("WEIGHT_DRV", "unable to access accel_axis_weight_if")
          
    endfunction

    task do_reset();
      
        vif.drv_cp.tdata  <= '0;
        vif.drv_cp.tkeep  <= '0;
        vif.drv_cp.tlast  <= 0;
        vif.drv_cp.tuser  <= '0;
        vif.drv_cp.tvalid <= 0;
        @(posedge vif.clk iff vif.rst_n);
        `uvm_info("WEIGHT_DRV", "Reset done", UVM_MEDIUM)
        $display("=========================================================================================================================================");
      
    endtask

    task send_tile();
      
        logic [127:0] tdata;
        logic [7:0]   tuser;
        int           col;
        int           beats_per_row;
        logic         is_last_beat;

        beats_per_row = (TB_COLS + 5) / 6;

        for(int row = 0; row < TB_ROWS; row++) begin
            for(int beat = 0; beat < beats_per_row; beat++) begin

                // Step 1 — Clear tdata
                tdata = 128'b0;

                // Step 2 — Pack up to 6 weight packets
                for(int p = 0; p < 6; p++) begin
                    col = beat * 6 + p;
                    if(col < TB_COLS) begin
                        tdata[p*20 +: 20] = {
                            t.idx1[row*TB_COLS + col],
                            t.idx0[row*TB_COLS + col],
                            t.w1  [row*TB_COLS + col],
                            t.w0  [row*TB_COLS + col]
                        };
                    end
                end

                // Step 3 — Build tuser
                is_last_beat = (row == TB_ROWS-1) &&
                               (beat == beats_per_row-1);
                tuser = {
                    t.sparse_mask,
                    t.sparsity_mode,
                    is_last_beat,
                    1'b1
                };

                `uvm_info("WEIGHT_DRV",$sformatf("Row=%0d Beat=%0d last=%0b",row, beat, is_last_beat), UVM_HIGH)

                // Step 4 — Drive beat
                @(vif.drv_cp);
                vif.drv_cp.tdata  <= tdata;
                vif.drv_cp.tkeep  <= 16'hFFFF;
                vif.drv_cp.tuser  <= tuser;
                vif.drv_cp.tlast  <= is_last_beat;
                vif.drv_cp.tvalid <= 1;

                // Step 5 — Wait for handshake
                @(posedge vif.clk iff vif.drv_cp.tready);

                // Step 6 — Deassert on last beat
                if(is_last_beat) begin
                    vif.drv_cp.tvalid <= 0;
                    vif.drv_cp.tlast  <= 0;
                end

            end
        end

        `uvm_info("WEIGHT_DRV", "Tile complete", UVM_MEDIUM)

    endtask

    task run_phase(uvm_phase phase);
      
        do_reset();
        forever begin
            seq_item_port.get_next_item(t);
            send_tile();
            seq_item_port.item_done();
        end
      
    endtask

endclass


class axis_weight_mon extends uvm_monitor;

    `uvm_component_utils(axis_weight_mon)

    uvm_analysis_port #(axis_weight_tnx) send;
    virtual accel_axis_weight_if          vif;
    axis_weight_tnx                       t;

    function new(string name = "axis_weight_mon",uvm_component parent = null);

        super.new(name, parent);

    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
      
        send = new("send", this);
        if(!uvm_config_db #(virtual accel_axis_weight_if)::get(this, "", "weight_if", vif))
            `uvm_fatal("WEIGHT_MON","unable to access accel_axis_weight_if")
          
    endfunction

    task run_phase(uvm_phase phase);
      
        int beats_per_row;
        beats_per_row = (TB_COLS + 5) / 6;

        forever begin
            // Fresh transaction for each tile
            t = axis_weight_tnx::type_id::create("t");

            // Collect all beats for one complete tile
            for(int row = 0; row < TB_ROWS; row++) begin
                for(int beat = 0; beat < beats_per_row; beat++) begin

                    // Wait for valid handshake
                    @(posedge vif.clk iff (vif.tvalid && vif.tready));

                    // Capture tuser on first beat only
                    if(row == 0 && beat == 0) begin
                        t.sparsity_mode = sparsity_mode_e'(vif.tuser[3:2]);
                        t.sparse_mask   = vif.tuser[7:4];
                    end

                    // Unpack tdata into transaction fields
                    for(int p = 0; p < 6; p++) begin
                        int col;
                        col = beat * 6 + p;
                        if(col < TB_COLS) begin
                            t.w0  [row*TB_COLS+col] = vif.tdata[p*20    +: 8];
                            t.w1  [row*TB_COLS+col] = vif.tdata[p*20+8  +: 8];
                            t.idx0[row*TB_COLS+col] = vif.tdata[p*20+16 +: 2];
                            t.idx1[row*TB_COLS+col] = vif.tdata[p*20+18 +: 2];
                        end
                    end

                end
            end

            `uvm_info("WEIGHT_MON", $sformatf("w0[0]=%0d w1[0]=%0d idx0[0]=%0d idx1[0]=%0d", t.w0[0], t.w1[0], t.idx0[0], t.idx1[0]), UVM_MEDIUM)
            `uvm_info("WEIGHT_MON", "Weight tile captured", UVM_MEDIUM)
            send.write(t);

        end
    endtask

endclass


class axis_weight_agent extends uvm_agent;

  `uvm_component_utils(axis_weight_agent)
  
  axis_weight_drv drv;
  axis_weight_mon mon;

  uvm_analysis_port #(axis_weight_tnx) aport;
  uvm_sequencer #(axis_weight_tnx) seqr;

  function new(string inst = "axis_weight_agent", uvm_component parent = null);
  
    super.new(inst,parent);
  
  endfunction
  
  
  virtual function void build_phase(uvm_phase phase);
  
    super.build_phase(phase);
    
    aport = new("aport",this);
    seqr = uvm_sequencer #(axis_weight_tnx)::type_id::create("seqr",this);
    drv = axis_weight_drv::type_id::create("drv",this);
    mon = axis_weight_mon::type_id::create("mon",this);
  
  endfunction
  
  virtual function void connect_phase(uvm_phase phase);
  
    super.connect_phase(phase);
    
    drv.seq_item_port.connect(seqr.seq_item_export);
    mon.send.connect(aport);
  
  endfunction

endclass


`endif