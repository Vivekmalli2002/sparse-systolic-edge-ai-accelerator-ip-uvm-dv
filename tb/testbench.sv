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
`include "accel_env.sv"
`include "accel_sequences.sv"
`include "tests.sv"

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
  
  
  //DUT instantiation

  accel_top_v18 
     #(
       .ROWS_P(TB_ROWS), //16 replace with ROWS
       .COLS_P(TB_COLS)  //16 replace with COLS
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
  

  initial begin
    
    //Configuration set
    uvm_config_db #(virtual accel_axil_if)::set(null,"*","axil_if",axil_if);
    uvm_config_db #(virtual accel_axis_weight_if)::set(null,"*","weight_if",weight_if);
    uvm_config_db #(virtual accel_axis_activation_if)::set(null,"*","act_if",act_if);
    uvm_config_db #(virtual accel_axis_result_if)::set(null,"*","result_if",result_if);
    
    
  end
  
  initial begin
    
    run_test("accel_sanity_test");
    
  end
  
  initial begin
    $dumpfile("dump.vcd");
    $dumpvars;
    #200000;
    $finish();
    
  end

  
endmodule