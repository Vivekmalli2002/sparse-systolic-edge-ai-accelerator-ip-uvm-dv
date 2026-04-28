interface accel_axil_if 
  #(
     parameter int AXIL_ADDR_WIDTH = 12,
     parameter int AXIL_DATA_WIDTH = 32,
     parameter int AXIL_STRB_WIDTH = AXIL_DATA_WIDTH / 8
  )(input logic clk,
    input logic rst_n);
  
  // Write Address Channel
  logic [AXIL_ADDR_WIDTH-1:0]    awaddr;
  logic [2:0]                    awprot;
  logic                          awvalid;
  logic                          awready;
    
    // Write Data Channel
  logic [AXIL_DATA_WIDTH-1:0]    wdata;
  logic [AXIL_STRB_WIDTH-1:0]    wstrb;
  logic                          wvalid;
  logic                          wready;
    
    // Write Response Channel
  logic [1:0]                    bresp;
  logic                          bvalid;
  logic                          bready;
    
    // Read Address Channel
  logic [AXIL_ADDR_WIDTH-1:0]    araddr;
  logic [2:0]                    arprot;
  logic                          arvalid;
  logic                          arready;
    
    // Read Data Channel
  logic [AXIL_DATA_WIDTH-1:0]    rdata;
  logic [1:0]                    rresp;
  logic                          rvalid;
  logic                          rready;
  
  clocking drv_cp @(posedge clk);
    
    default input #1step;
    output awaddr,awprot,awvalid,wdata,wstrb,wvalid,bready,araddr,arprot,arvalid,rready;
    input awready,wready,bresp,bvalid,arready,rdata,rresp,rvalid;
    
  endclocking
  
  
  clocking mon_cp @(posedge clk);
    
    default input #1step;
    input awaddr,awprot,awvalid,wdata,wstrb,wvalid,bready,araddr,arprot,arvalid,rready;
    input awready,wready,bresp,bvalid,arready,rdata,rresp,rvalid;
    
  endclocking
  
  
  modport DRV (clocking drv_cp,input rst_n);
  modport MON (clocking mon_cp, input rst_n);
  
endinterface


interface accel_axis_weight_if
  #(
    parameter int AXIS_DATA_WIDTH = 128,
    parameter int AXIS_USER_WIDTH = 8
  )(
    input logic clk,
    input logic rst_n
  );
  
  
  logic [AXIS_DATA_WIDTH-1:0]    tdata;
  logic [AXIS_DATA_WIDTH/8-1:0]  tkeep;
  logic                          tlast;
  logic [AXIS_USER_WIDTH-1:0]    tuser;
  logic                          tvalid;
  logic                          tready;
  
  
  clocking drv_cp @(posedge clk);
    
    default input #1step;
    input tready;
    output tdata,tkeep,tlast,tuser,tvalid;
    
  endclocking
  
  
  clocking mon_cp @(posedge clk);
    
    default input #1step;
    input tready,tdata,tkeep,tlast,tuser,tvalid;
    
  endclocking
  
  
  modport DRV (clocking drv_cp, input rst_n);
  modport MON (clocking mon_cp, input rst_n);
  
endinterface


interface accel_axis_activation_if
  #(
    parameter int AXIS_DATA_WIDTH = 128
  )(
    input logic clk,
    input logic rst_n
  );
  
  logic [AXIS_DATA_WIDTH-1:0]    tdata;
  logic [AXIS_DATA_WIDTH/8-1:0]  tkeep;
  logic                          tlast;
  logic                          tvalid;
  logic                          tready;
  
  
  clocking drv_cp @(posedge clk);
    
    default input #1step;
    input tready;
    output tdata,tkeep,tlast,tvalid;
    
  endclocking
  
  
  clocking mon_cp @(posedge clk);
    
    default input #1step;
    input tready,tdata,tkeep,tlast,tvalid;
    
  endclocking
  
  modport DRV (clocking drv_cp, input rst_n);
  modport MON (clocking mon_cp, input rst_n);
  
endinterface


interface accel_axis_result_if
  #(
    parameter int AXIS_DATA_WIDTH = 128,
    parameter int AXIS_USER_WIDTH = 8
  )(
    input logic clk,
    input logic rst_n
  );
  
  logic [AXIS_DATA_WIDTH-1:0]    tdata;
  logic [AXIS_DATA_WIDTH/8-1:0]  tkeep;
  logic                          tlast;
  logic [AXIS_USER_WIDTH-1:0]    tuser;
  logic                          tvalid;
  logic                          tready;
  
  
  
  clocking drv_cp @(posedge clk);
    
    default input #1step;
    output tready;
    
  endclocking
  
  clocking mon_cp @(posedge clk);
    
    default input #1step;
    input tdata,tkeep,tlast,tuser,tvalid,tready;
    
  endclocking
  
  modport DRV (clocking drv_cp, input rst_n);
  
  modport MON (clocking mon_cp, input rst_n);
  
endinterface


interface accel_dut_probes_if(input logic clk);
  
    logic [2:0] state;           // FSM state
    logic       wgt_buf_tile_ready;
    logic       done;
    logic mode_dense;
  
endinterface