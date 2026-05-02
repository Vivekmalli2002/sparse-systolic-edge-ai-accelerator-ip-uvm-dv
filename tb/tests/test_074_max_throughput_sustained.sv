`ifndef TEST_074_MAX_THROUGHPUT_SUSTAINED_SV
`define TEST_074_MAX_THROUGHPUT_SUSTAINED_SV

class test_074_max_throughput_sustained extends base_test;
  `uvm_component_utils(test_074_max_throughput_sustained)

  localparam int TOTAL_VECTORS    = 100;
  localparam int PIPELINE_LATENCY = 48;

  function new(string name = "test_074_max_throughput_sustained", uvm_component parent = null);
    super.new(name, parent);
  endfunction

  virtual task run_phase(uvm_phase phase);
    bit [31:0] tot_cyc, stall_cyc, mac_cnt;
    real        gmacs;
    phase.raise_objection(this);

    $display("==========================Test_074 : Maximum Throughput Sustained (100 vectors) - Start==================================");

    w_tile_seq   = accel_weight_tile_seq::type_id::create("w_tile_seq");
    a_stream_seq = accel_act_stream_seq::type_id::create("a_stream_seq");
    w_tile_tnx   = axis_weight_tnx::type_id::create("w_tile_tnx");
    a_stream_tnx = axis_act_tnx::type_id::create("a_stream_tnx");
    rd_seq       = accel_csr_read_seq::type_id::create("rd_seq");

    env.sco.flush_queues();

    // Build weight tile (all ones)
    for (int i = 0; i < TB_ROWS * TB_COLS; i++) begin
      w_tile_tnx.w0[i] = 1; 
      w_tile_tnx.w1[i] = 1;
      w_tile_tnx.idx0[i] = 0;
      w_tile_tnx.idx1[i] = 1;
    end
    w_tile_tnx.sparsity_mode = SPARSITY_DENSE;
    w_tile_tnx.sparse_mask   = 4'hF;

    // Activation vector (all ones)
    a_stream_tnx.a0 = 1; a_stream_tnx.a1 = 1;
    a_stream_tnx.a2 = 1; a_stream_tnx.a3 = 1;
    a_stream_tnx.is_last    = 1'b0;
    a_stream_tnx.mode_dense = 1'b1;

    // Run compute normally – scoreboard verifies results
    $display("                Running %0d vectors dense, all-ones (max throughput)...", TOTAL_VECTORS);
    run_compute_test(w_tile_tnx, a_stream_tnx, 32'h0000_0001, TOTAL_VECTORS, "T074");

        // Read performance counters
    rd_seq.csr_addr = CSR_PERF_CYCLES;
    rd_seq.start(env.axil_a.seqr); 
    tot_cyc   = rd_seq.csr_rdata;
    
    rd_seq.csr_addr = CSR_PERF_STALL; 
    rd_seq.start(env.axil_a.seqr); 
    stall_cyc = rd_seq.csr_rdata;
    
    rd_seq.csr_addr = CSR_PERF_MAC;  
    rd_seq.start(env.axil_a.seqr); 
    mac_cnt   = rd_seq.csr_rdata;

    $display("                Performance: cycles=%0d  stalls=%0d  MACs=%0d", tot_cyc, stall_cyc, mac_cnt);

    // Verify zero stalls
    if (stall_cyc != 0)
      `uvm_error(get_name(), $sformatf("STALL=%0d – backpressure during sustained load!", stall_cyc))
    else
      $display("    Zero stall cycles. Sustained throughput verified.");

    // Report correct GMACS using the same math as the base test's performance report
    if (tot_cyc > 0) begin
      real throughput = real'(mac_cnt) / real'(tot_cyc);
      real gmacs = 2.0 * throughput * CLK_FREQ_GHZ;
      $display("    Achieved GMACS = %.2f", gmacs);
    end

    $display("===================================================Test_074 : End of the test=================================================================");
    `uvm_info("COVERAGE", $sformatf("Coverage = %0.2f%%", $get_coverage()), UVM_MEDIUM)
    phase.drop_objection(this);
  endtask
endclass

`endif