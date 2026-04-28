module accel_sva_coverage
  import accel_pkg_v18::*;
  import accel_tb_pkg::*;
  (
   input logic clk,
    input logic rst_n,
    
    //AXIL signals
    input logic awvalid,
    input logic awready,
    input logic wvalid,
    input logic wready,
    input logic bvalid,
    input logic bready,
    input logic arvalid,
    input logic arready,
    input logic rvalid,
    input logic rready,
    input logic [1:0] bresp,
    input logic [1:0] rresp,
    
    //AXIS Weight Siganals
    input logic [AXIS_DATA_WIDTH-1:0] w_tdata,
    input logic w_tlast,
    input logic w_tvalid,
    input logic w_tready,

    //AXIS Act Signals
    input logic [AXIS_DATA_WIDTH-1:0] a_tdata,
    input logic a_tlast,
    input logic a_tvalid,
    input logic a_tready,
    
    //AXIS Result Signals
    input logic [AXIS_DATA_WIDTH-1:0] r_tdata,
    input logic r_tlast,
    input logic r_tvalid,
    input logic r_tready,
    
    //DUT
    input logic wgt_tile_start,
    input compute_state_e state,
    input logic compute_en,
    input logic busy,
    input logic done
  
  );
  
  default clocking cb @(posedge clk); endclocking
  default disable iff (!rst_n);
  
  
  //AXIL Protocol
  property p_awvalid_stable;
    
    (awvalid && !awready) |=> $stable(awvalid);
    
  endproperty
  
  
  property p_awvalid_no_x;
    
    !$isunknown(awvalid);
    
  endproperty
  
  
  property p_wvalid_stable;
    
    (wvalid && !wready) |=> $stable(wvalid);
    
  endproperty
  
  
  property p_wvalid_no_x;
    
    !$isunknown(wvalid);
    
  endproperty
  
  
  property p_bvalid_stable;
    
    (bvalid && !bready) |=> $stable(bvalid);
    
  endproperty
  
  
  property p_bvalid_no_x;
    
    !$isunknown(bvalid);
    
  endproperty
  
  
  property p_bresp_must_be_ok;
    
    bvalid |-> (bresp == 2'b00);
    
  endproperty
  
  
  property p_arvalid_stable;
    
    (arvalid && !arready) |=> $stable(arvalid);
    
  endproperty
  
  
  property p_arvalid_no_x;
    
    !$isunknown(arvalid);
    
  endproperty
  
  
  property p_rvalid_stable;
    
    (rvalid && !rready) |=> $stable(rvalid);
    
  endproperty
  
  
  property p_rvalid_no_x;
    
    !$isunknown(rvalid);
    
  endproperty
  
  
  property p_rresp_must_be_ok;
    
    rvalid |-> (rresp == 2'b00);
    
  endproperty



  //AXIS Weight Protocol
  property p_w_tvalid_stable;
    
    (w_tvalid && !w_tready) |=> $stable(w_tvalid);
    
  endproperty
  
  
  property p_w_tdata_stable;
    
    (w_tvalid && !w_tready) |=> $stable(w_tdata);
    
  endproperty
  
  
  property p_w_tlast_stable;
    
    (w_tvalid && !w_tready) |=> $stable(w_tlast);
    
  endproperty
  
  
  property p_w_tvalid_no_x;
    
    !$isunknown(w_tvalid);
    
  endproperty
  
  
  property p_w_tdata_no_x;
    
   w_tvalid |-> !$isunknown(w_tdata);
    
  endproperty
  
  
  //AXIS Act Protocol
  property p_a_tvalid_stable;
    
    (a_tvalid && !a_tready) |=> $stable(a_tvalid);
    
  endproperty
  
  
  property p_a_tdata_stable;
    
    (a_tvalid && !a_tready) |=> $stable(a_tdata);
    
  endproperty
  
  
  property p_a_tlast_stable;
    
    (a_tvalid && !a_tready) |=> $stable(a_tlast);
    
  endproperty
  
  
  property p_a_tvalid_no_x;
    
    !$isunknown(a_tvalid);
    
  endproperty
  
  
  property p_a_tdata_no_x;
    
    a_tvalid |-> !$isunknown(a_tdata);
    
  endproperty
  
  
  //AXIS Result Protocol
  property p_r_tvalid_stable;
    
    (r_tvalid && !r_tready) |=> $stable(r_tvalid);
    
  endproperty
  
  
  property p_r_tdata_stable;
    
    (r_tvalid && !r_tready) |=> $stable(r_tdata);
    
  endproperty
  
  
  property p_r_tlast_stable;
    
    (r_tvalid && !r_tready) |=> $stable(r_tlast);
    
  endproperty
  
  
  property p_r_tvalid_no_x;
    
    !$isunknown(r_tvalid);
    
  endproperty
  
  
  property p_r_tdata_no_x;
    
    r_tvalid |-> !$isunknown(r_tdata);
    
  endproperty
  
  
  //DUT
  property p_busy_when_not_idle;
    
    (state != S_IDLE) |-> busy;
    
  endproperty
  
  
  property p_done_after_drain;
    
    (state == S_DRAIN) |-> ##[1:$] $rose(done);

  endproperty
  
  
  property p_wgt_tile_start_when_state_idle_or_done;
    
    wgt_tile_start |-> (state == S_IDLE || state == S_DONE);
    
  endproperty
  
  
  property p_compute_en_active_in_state_stream_and_drain;
    
    compute_en |-> (state == S_STREAM || state == S_DRAIN)
    
  endproperty 
  
  
  
  
  PA001_awvalid_stable: assert property(p_awvalid_stable)
    else `uvm_error("PA001", "awvalid deasserted before awready");
    
  
  PA002_awvalid_no_x: assert property(p_awvalid_no_x)
    else `uvm_error("PA002","awvalid is unkown");
    
  
  PA003_wvalid_stable: assert property(p_wvalid_stable)
    else `uvm_error("PA003","wvalid deasserted before wready");

  
  PA004_wvalid_no_x: assert property(p_wvalid_no_x)
    else `uvm_error("PA004","wvalid is unkown");
  
  
  PA005_bvalid_stable: assert property(p_bvalid_stable)
    else `uvm_error("PA005","bvalid deasserted before bready");


  PA006_bvalid_no_x: assert property(p_bvalid_no_x)
    else `uvm_error("PA006","pvalid is unkown");
    
    
  PA007_bresp_must_be_ok: assert property(p_bresp_must_be_ok)
    else `uvm_error("PA007","when bvalid then bresp is not ok");
      
  
  PA008_arvalid_stable: assert property(p_arvalid_stable)
    else `uvm_error("PA008","arvalid deasserted before arready");


  PA009_arvalid_no_x: assert property(p_arvalid_no_x)
    else `uvm_error("PA009","arvalis is unkown");


  PA010_rvalid_stable: assert property(p_rvalid_stable)
    else `uvm_error("PA010","rvalid deasserted before rready");


  PA011_rvalid_no_x: assert property(p_rvalid_no_x)
    else `uvm_error("PA011","rvalid is unkown");


  PA012_rresp_must_be_ok: assert property(p_rresp_must_be_ok)
    else `uvm_error("PA012","when rvalid then rresp is not ok");


  PA013_w_tvalid_stable: assert property(p_w_tvalid_stable)
    else `uvm_error("PA013","w_tvalid deasserted before w_tready");

   
  PA014_w_tdata_stable: assert property(p_w_tdata_stable)
    else `uvm_error("PA014","w_tvalid then w_tdata is not stable");  
  
  
  PA015_w_tlast_stable: assert property(p_w_tlast_stable)
    else `uvm_error("PA015","w_tlast deasserted before w_tready");
    
  
  PA016_w_tvalid_no_x: assert property(p_w_tvalid_no_x)
    else `uvm_error("PA016","w_tvalid is unkown");
  
    
  PA017_w_tdata_no_x: assert property(p_w_tdata_no_x)
    else `uvm_error("PA017","w_tdata is unkown");
    
  
  PA018_a_tvalid_stable: assert property(p_a_tvalid_stable)
    else `uvm_error("PA018","a_tvalid deasserted before a_tready");

   
  PA019_a_tdata_stable: assert property(p_a_tdata_stable)
    else `uvm_error("PA019","a_tvalid then a_tdata is not stable");  
  
  
  PA020_a_tlast_stable: assert property(p_a_tlast_stable)
    else `uvm_error("PA020","a_tlast deasserted before a_tready");
    
  
  PA021_a_tvalid_no_x: assert property(p_a_tvalid_no_x)
    else `uvm_error("PA021","a_tvalid is unkown");
  
    
  PA022_a_tdata_no_x: assert property(p_a_tdata_no_x)
    else `uvm_error("PA022","a_tdata is unkown");

    
  PA023_r_tvalid_stable: assert property(p_r_tvalid_stable)
    else `uvm_error("PA023","r_tvalid deasserted before r_tready");

   
  PA024_r_tdata_stable: assert property(p_r_tdata_stable)
    else `uvm_error("PA024","r_tvalid then r_tdata is not stable");  
  
  
  PA025_r_tlast_stable: assert property(p_r_tlast_stable)
    else `uvm_error("PA025","r_tlast deasserted before r_tready");
    
  
  PA026_r_tvalid_no_x: assert property(p_r_tvalid_no_x)
    else `uvm_error("PA026","r_tvalid is unkown");
  
    
  PA027_r_tdata_no_x: assert property(p_r_tdata_no_x)
    else `uvm_error("PA027","r_tdata is unkown which mean DUT Data path was broken or wrong or filled with unkown data x or z");
        
  
  PA028_busy_when_not_idle: assert property(p_busy_when_not_idle)
    else `uvm_error("PA028","busy should be high when current state is not S_IDLE");
    
  
  PA029_wgt_tile_start_when_state_idle_or_done: assert property(p_wgt_tile_start_when_state_idle_or_done)
    else `uvm_error("PA029","wgt_tile_start should be high only in the states S_STREAM || S_DONE");
  
  
  PA030_compute_en_active_in_state_stream_and_drain: assert property(p_compute_en_active_in_state_stream_and_drain)
    else `uvm_error("PA030", "Compute_en should be active in only State STREAM & DRAIN");  
      
  
endmodule