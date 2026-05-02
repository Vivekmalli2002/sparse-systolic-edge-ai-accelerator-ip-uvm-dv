`timescale 1ns/1ps
`include "uvm_macros.svh"
`include "accel_tb_pkg.sv"
`include "accel_interfaces.sv"
`include "accel_transactions.sv"
`include "accel_axil_agent.sv"
`include "accel_axis_weight_agent.sv"
`include "accel_axis_act_agent.sv"
`include "accel_axis_result_agent.sv"
`include "accel_scoreboard.sv"
`include "accel_coverage_subscriber.sv"
`include "accel_env.sv"
`include "accel_sequences.sv"
`include "base_tests.sv"
`include "accel_sva.sv"
`include "test_files.sv"

import uvm_pkg::*;
import accel_pkg_v18::*;
import accel_tb_pkg::*;
 



module tb_top;
  
  logic clk,rst_n;
  logic irq_out,busy,done;
  logic [2:0] state_out;
  
  
  initial begin
    
    clk = 0;
    rst_n = 0;
    #100;
    rst_n = 1;
    
  end
  
  always #2.5 clk = ~ clk;
  
  
  //Interface instantiation
  accel_axil_if axil_if(clk,rst_n);
  
  accel_axis_weight_if weight_if(clk,rst_n);
  
  accel_axis_activation_if act_if(clk,rst_n);
  
  accel_axis_result_if result_if(clk,rst_n);
  
  accel_dut_probes_if probe_if(clk);
  
  
  assign probe_if.state           = dut.u_control.u_compute.state_q;
  assign probe_if.wgt_buf_tile_ready = dut.wgt_buf_tile_ready;
  assign probe_if.done            = done;
  assign probe_if.mode_dense = dut.u_control.mode_dense;
  
  
  // ---- Fault injection bridge: probe_if.inject_parity_error -> DUT ----
  always @(posedge probe_if.clk) begin
    if (probe_if.inject_parity_error) begin
      $display("*** inject_parity_error detected — forcing parity_error for 1 cycle ***");
      // Assuming the DUT's parity error signal is at this path:
      force dut.u_control.u_csr.ctrl_abort = 1'b1;
      // Release on the next clock edge
      @(posedge probe_if.clk);
      release dut.u_control.u_csr.ctrl_abort;
      // Autonomously clear the injection flag so the test knows it fired
      probe_if.inject_parity_error <= 0;
    end
  end
    
  
  //DUT instantiation

  accel_top_v18 
     #(
       .ROWS_P(TB_ROWS), //16 replace with ROWS
       .COLS_P(TB_COLS),  //16 replace with COLS
       .WEIGHT_FIFO_DEP(8),
        .OUTPUT_FIFO_DEP(OFIFO_DEPTH),
        .ENABLE_ICG(1),
        .ENABLE_PARITY(1),
        .ENABLE_POSTPROC(1)
       ) dut (
       .clk(clk),
       .rst_n(rst_n),
       .scan_enable(1'b0),
       
       //AXIL Signals
       .s_axil_awaddr(axil_if.awaddr),
       .s_axil_awprot(axil_if.awprot),
       .s_axil_awvalid(axil_if.awvalid),
       .s_axil_awready(axil_if.awready),
       .s_axil_wdata(axil_if.wdata),
       .s_axil_wstrb(axil_if.wstrb),
       .s_axil_wvalid(axil_if.wvalid),
       .s_axil_wready(axil_if.wready),
       .s_axil_bresp(axil_if.bresp),
       .s_axil_bvalid(axil_if.bvalid),
       .s_axil_bready(axil_if.bready),
       .s_axil_araddr(axil_if.araddr),
       .s_axil_arprot(axil_if.arprot),
       .s_axil_arvalid(axil_if.arvalid),
       .s_axil_arready(axil_if.arready),
       .s_axil_rdata(axil_if.rdata),
       .s_axil_rresp(axil_if.rresp),
       .s_axil_rvalid(axil_if.rvalid),
       .s_axil_rready(axil_if.rready),
       
       //AXIS Weight Input
       .s_axis_weight_tdata(weight_if.tdata),
       .s_axis_weight_tkeep(weight_if.tkeep),
       .s_axis_weight_tlast(weight_if.tlast),
       .s_axis_weight_tuser(weight_if.tuser),
       .s_axis_weight_tvalid(weight_if.tvalid),
       .s_axis_weight_tready(weight_if.tready),
       
       //AXIS Activation Input
       .s_axis_act_tdata(act_if.tdata),
       .s_axis_act_tkeep(act_if.tkeep),
       .s_axis_act_tlast(act_if.tlast),
       .s_axis_act_tvalid(act_if.tvalid),
       .s_axis_act_tready(act_if.tready),
       
       //AXIS Result Output
       .m_axis_result_tdata(result_if.tdata),
       .m_axis_result_tkeep(result_if.tkeep),
       .m_axis_result_tlast(result_if.tlast),
       .m_axis_result_tuser(result_if.tuser),
       .m_axis_result_tvalid(result_if.tvalid),
       .m_axis_result_tready(result_if.tready),
       
       //Status Signals
       .irq_out (irq_out),
       .busy (busy),
       .done (done),
       .state_out (state_out)     
     );
 
  
  
  bind accel_top_v18 accel_sva u_sva(
    
    .clk(clk),
    .rst_n(rst_n),
    //AXIL
    .awvalid(s_axil_awvalid),
    .awready(s_axil_awready),
    .wvalid(s_axil_wvalid),
    .wready(s_axil_wready),
    .bready(s_axil_bready),
    .bvalid(s_axil_bvalid),
    .bresp(s_axil_bresp),
    .arvalid(s_axil_arvalid),
    .arready(s_axil_arready),
    .rvalid(s_axil_rvalid),
    .rresp(s_axil_rresp),
    .rready(s_axil_rready),
    //AXIS Weight
    .w_tvalid(s_axis_weight_tvalid),
    .w_tlast(s_axis_weight_tlast),
    .w_tdata(s_axis_weight_tdata),
    .w_tready(s_axis_weight_tready),
    //AXIS Activation
    .a_tvalid(s_axis_act_tvalid),
    .a_tlast(s_axis_act_tlast),
    .a_tdata(s_axis_act_tdata),
    .a_tready(s_axis_act_tready),
    //AXIS Result
    .r_tvalid(m_axis_result_tvalid),
    .r_tready(m_axis_result_tready),
    .r_tdata(m_axis_result_tdata),
    .r_tlast(m_axis_result_tlast),
    
    .wgt_tile_start(u_control.wgt_tile_start),
    .state(state_out),
    .compute_en(u_control.compute_en),
    .busy(busy),
    .sparsity_mode(dut.sparsity_cfg),
    .ofifo_full(dut.ofifo_full),
    .done(done)
  
  );
  

  initial begin
    
    //Configuration set
    uvm_config_db #(virtual accel_axil_if)::set(null,"*","axil_if",axil_if);
    uvm_config_db #(virtual accel_axis_weight_if)::set(null,"*","weight_if",weight_if);
    uvm_config_db #(virtual accel_axis_activation_if)::set(null,"*","act_if",act_if);
    uvm_config_db #(virtual accel_axis_result_if)::set(null,"*","result_if",result_if);
    uvm_config_db #(virtual accel_dut_probes_if)::set(null,"*","probe_if",probe_if);
    
    
  end
  
  initial begin
    
    //run_test("test_001_CSR_reset_sanity");
    //run_test("test_002_CSR_write_read_back");
    //run_test("test_003_CSR_soft_reset");
    //run_test("test_004_CSR_verify_IRQ_source");
    //run_test("test_005_CSR_perf_counters");
    //run_test("test_010_dense_allones");
    //run_test("test_011_dense_identity_weights");
    //run_test("test_012_dense_negative_weights");
    //run_test("test_013_dense_max_weights");
    //run_test("test_014_dense_8vectors");
    //run_test("test_015_sparse_2_4");
    //run_test("test_016_sparse_1_4");
    //run_test("test_017_sparse_4_8");
    //run_test("test_018_dense_32vectors");
    //run_test("test_019_dense_100vectors");
    //run_test("test_020_sparse_2_4_8vectors");
    //run_test("test_021_sparse_2_4_100vectors");
    //run_test("test_022_sparse_1_4_8vectors");
    //run_test("test_023_sparse_1_4_100vectors");
    //run_test("test_024_sparse_4_8_8vectors");
    //run_test("test_025_sparse_4_8_100vectors");
    //run_test("test_040_cap_csr_readonly");
    //run_test("test_041_axil_aw_w_ordering");
    //run_test("test_042_axil_read_during_write");
    //run_test("test_044_axil_reserved_addr_write");
    //run_test("test_045_result_tready_backpressure");
    //run_test("test_046_weight_tready_mid_tile");
    //run_test("test_047_act_tvalid_gap");
    //run_test("test_048_result_tvalid_tlast");
    //run_test("test_049_simultaneous_backpressure");
    //run_test("test_050_postproc_bias_add");
    //run_test("test_051_postproc_scale_shift");
    //run_test("test_052_postproc_sat_upper");
    //run_test("test_053_postproc_sat_lower");
    //run_test("test_054_activation_relu_vs_leaky");
    //run_test("test_060_soft_reset_from_stream");
    //run_test("test_061_hard_reset_during_compute");
    //run_test("test_062_irq_mask_during_compute");
    //run_test("test_063_csr_write_during_compute");
    //run_test("test_064_weight_tile_reuse");
    //run_test("test_070_constrained_random_all_modes");
    //run_test("test_071_rand_postproc_config");
    //run_test("test_072_fsm_transition_coverage");
    //run_test("test_073_axi_handshake_coverage");
    run_test("test_074_max_throughput_sustained");


  end
  
  initial begin
    #3000000;
    $finish();
    
  end
  
endmodule