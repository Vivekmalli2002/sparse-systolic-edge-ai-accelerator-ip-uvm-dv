`ifndef BASE_TESTS_SV
`define BASE_TESTS_SV


class base_test extends uvm_test;
  
  `uvm_component_utils(base_test)
  
  accel_csr_write_seq    wr_seq;
  accel_csr_read_seq     rd_seq;
  accel_weight_tile_seq  w_tile_seq;
  accel_act_stream_seq   a_stream_seq;
  axis_weight_tnx        w_tile_tnx;
  axis_act_tnx           a_stream_tnx;
  
  accel_env env;
  
  virtual accel_axil_if             vif;
  virtual accel_axis_weight_if      weight_if;
  virtual accel_axis_activation_if  act_if;
  virtual accel_dut_probes_if       probe_if;
  
  
  function new(string inst = base_test, uvm_component parent = null);
    
    super.new(inst, parent);
    
  endfunction
  
  
  virtual function void build_phase(uvm_phase phase);
    
    super.build_phase(phase);
    
    if(!uvm_config_db #(virtual accel_axil_if)get(this,,axil_if,vif))
      `uvm_fatal(accel_functionality_baseTest,unable to access the interface accel_axil_if)
      
    if(!uvm_config_db #(virtual accel_axis_weight_if)get(this,,weight_if,weight_if))
      `uvm_fatal(accel_functionality_baseTest,unable to access the interface accel_axis_weight_if)
    
    if(!uvm_config_db #(virtual accel_axis_activation_if)get(this,,act_if,act_if))
      `uvm_fatal(accel_functionality_baseTest,unable to access the interface accel_axis_act_if)
      
    if(!uvm_config_db #(virtual accel_dut_probes_if)get(this,,probe_if,probe_if))
      `uvm_fatal(accel_functionality_baseTest,unable to access the interface accel_dut_probes_if)

    env = accel_envtype_idcreate(env,this);  
    
  endfunction
  
  
  virtual task run_phase(uvm_phase phase);
  endtask
  
  
   Reusable — every child test calls this
    task wait_for_reset();

        @(posedge vif.clk iff vif.rst_n === 1);

        repeat(5) @(posedge vif.clk);
        `uvm_info(BASE_TEST, Reset done — DUT ready, UVM_MEDIUM)

        $display(=========================================================================================================================================);

    endtask
  
  
  
  task run_compute_test(
    
    input axis_weight_tnx  w_tile,
    input axis_act_tnx     act_vec,
    input logic [310]     sparsity_cfg,
    input int              num_vectors,
    string test_name
    
  );
    
      wr_seq = accel_csr_write_seqtype_idcreate(wr_seq);
      rd_seq = accel_csr_read_seqtype_idcreate(rd_seq);

       Step 1 — Soft reset + clear
      $display(                Step 1  Soft Reset + Clear                 );
    
      wr_seq.csr_addr = CSR_CTRL;
      wr_seq.csr_data = 32'h0000_0048;
      wr_seq.start(env.axil_a.seqr);
      repeat(10) @(posedge vif.clk);

      wr_seq.csr_addr = CSR_CTRL;
      wr_seq.csr_data = 32'h0000_0008;
      wr_seq.start(env.axil_a.seqr);
      repeat(5) @(posedge vif.clk);
    

       Step 2 — Configure
      $display(                Step 2  Configure  CSR_TILE_CFG, CSR_ACT_TILE_CFG, CSR_SPARSITY, CSR_CTRL              );
    
      wr_seq.csr_addr = CSR_TILE_CFG;
      wr_seq.csr_data = {16'd1, 16'(num_vectors)};
      wr_seq.start(env.axil_a.seqr);

      wr_seq.csr_addr = CSR_ACT_TILE_CFG;
      wr_seq.csr_data = {16'd1, 16'd0};
      wr_seq.start(env.axil_a.seqr);

      wr_seq.csr_addr = CSR_SPARSITY;
      wr_seq.csr_data = sparsity_cfg;
      wr_seq.start(env.axil_a.seqr);

      wr_seq.csr_addr = CSR_CTRL;
      wr_seq.csr_data = 32'h0000_0001;
      wr_seq.start(env.axil_a.seqr);
      repeat(5) @(posedge vif.clk);
    

       Step 3 — Stream weights
      $display(                Step 3  Stream weights                 );
    
      w_tile_seq.t = w_tile;
      w_tile_seq.start(env.weight_a.seqr);
      @(posedge vif.clk iff probe_if.wgt_buf_tile_ready);

       Step 4 — Enable + Start
      $display(                Step 4  Enable + Start                 );
    
      wr_seq.csr_addr = CSR_CTRL;
      wr_seq.csr_data = 32'h0000_0003;
      wr_seq.start(env.axil_a.seqr);
    
      repeat(5) @(posedge vif.clk);
     
      @(posedge vif.clk iff probe_if.state === S_STREAM);
    

       Step 5 — Stream activations (one per vector)
      $display(                Step 5  Stream activations (one per vector)                 );
    
      for(int v = 0; v  num_vectors; v++) begin
          act_vec.is_last = (v == num_vectors-1);
          a_stream_seq.t = act_vec;
          a_stream_seq.start(env.act_a.seqr);
      end

       Step 6 — Wait done
      $display(                Step 6  Wait for computation done                 );
    
      @(posedge vif.clk iff probe_if.done === 1'b1);
      repeat(10) @(posedge vif.clk);
    
       Step 7 — Performance report
      read_and_report_perf(test_name, num_vectors, sparsity_cfg == 32'h0000_0001  1  0);
      

  endtask
  
  
  task read_and_report_perf(
        string test_name,
        int    num_vectors,
        logic  is_dense
    );
        logic [310] perf_cycles;
        logic [310] perf_stall;
        logic [310] perf_mac;
        logic [310] perf_zw;
        logic [310] perf_za;
        real         throughput;
        real         efficiency;
        real         sparsity_ratio;
        int          total_ops;
        real achieved_gmacs;
        real achieved_gops_1op;
        real achieved_gops_2op;

         Read counters (unchanged)
        rd_seq.csr_addr = CSR_PERF_CYCLES;
        rd_seq.start(env.axil_a.seqr);
        perf_cycles = rd_seq.csr_rdata;

        rd_seq.csr_addr = CSR_PERF_STALL;
        rd_seq.start(env.axil_a.seqr);
        perf_stall = rd_seq.csr_rdata;

        rd_seq.csr_addr = CSR_PERF_MAC;
        rd_seq.start(env.axil_a.seqr);
        perf_mac = rd_seq.csr_rdata;

        rd_seq.csr_addr = CSR_PERF_ZW;
        rd_seq.start(env.axil_a.seqr);
        perf_zw = rd_seq.csr_rdata;

        rd_seq.csr_addr = CSR_PERF_ZA;
        rd_seq.start(env.axil_a.seqr);
        perf_za = rd_seq.csr_rdata;

         Derived metrics
        total_ops = perf_mac + perf_zw + perf_za;

         Achieved metrics
        throughput = (perf_cycles  0) 
            real'(perf_mac)  real'(perf_cycles)  0.0;    fused dual‑MACs per cycle

         Each fused dual‑MAC = 2 TPU‑style MACs
        achieved_gmacs = 2.0  throughput  CLK_FREQ_GHZ;    TPU MACs per second

         Utilisation and sparsity efficiency (unchanged)
        efficiency = (perf_cycles  0) 
            (real'(perf_cycles - perf_stall)  real'(perf_cycles))  100.0  0.0;

        sparsity_ratio = (total_ops  0) 
            real'(perf_mac)  real'(total_ops)  100.0  0.0;

         Display section (unchanged layout)
        $display();
        $display(==============================================================);
        $display(  PERFORMANCE REPORT  %s, test_name);
        $display(==============================================================);
        $display(  Vectors processed    %0d,   num_vectors);
        $display(  Mode                 %0s,   is_dense  DENSE  SPARSE);
        $display(  Array size           %0dx%0d PEs, TB_ROWS, TB_COLS);
        $display(--------------------------------------------------------------);
        $display(  Total cycles         %0d,   perf_cycles);
        $display(  Stall cycles         %0d,   perf_stall);
        $display(  Active cycles        %0d,   perf_cycles - perf_stall);
        $display(  Utilization          %.1f%%, efficiency);
        $display(--------------------------------------------------------------);
        $display(  Useful MACs          %0d,   perf_mac);
        $display(  Zero weight skips    %0d,   perf_zw);
        $display(  Zero act skips       %0d,   perf_za);
        $display(  Total PE ops         %0d,   total_ops);
        $display(  Compute efficiency   %.1f%%, sparsity_ratio);
        $display(--------------------------------------------------------------);
        $display(  Throughput (MACscycle)  %.2f, throughput);
        $display(--------------------------------------------------------------);
        $display(  Peak MACscycle      %0d,      PEAK_MACS_PER_CYCLE);
        $display(  Peak GMACS           %.2f,     PEAK_GMACS);
        $display(  Peak GOPS           %.2f,     PEAK_GMACS  2);
        $display(--------------------------------------------------------------);
        $display(  Achieved GMACS       %.2f,     achieved_gmacs);
        $display(  Achieved GOPS       %.2f,     achieved_gmacs  2);  Each PE does 2 MACS - 2 Multiple + 2 addition 
        $display(==============================================================);
        $display();
    endtask
  
  
endclass


`endif