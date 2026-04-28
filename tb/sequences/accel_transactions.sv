`ifndef ACCEL_TRANSACTIONS_SV
`define ACCEL_TRANSACTIONS_SV

`include "uvm_macros.svh"
`include "accel_tb_pkg.sv"
import uvm_pkg::*;
import accel_pkg_v18::*;
import accel_tb_pkg::*;


// =========================================================
// Transaction 1 — AXI-Lite CSR
// =========================================================
class axil_csr_tnx extends uvm_sequence_item;

    // Stimulus — sequence sets these
    logic [AXIL_ADDR_WIDTH-1:0]  addr;   // CSR address — not rand
    logic                         we;     // 1=write 0=read — not rand
    rand logic [AXIL_DATA_WIDTH-1:0] wdata; // write data — rand

    // Response — DUT produces these, driver captures them
    logic [AXIL_DATA_WIDTH-1:0]  rdata;  // read data from DUT
    logic [1:0]                  resp;   // bresp or rresp from DUT

   `uvm_object_utils_begin(axil_csr_tnx)
        `uvm_field_int(addr,  UVM_ALL_ON)
        `uvm_field_int(we,    UVM_ALL_ON)
        `uvm_field_int(wdata, UVM_ALL_ON)
        `uvm_field_int(rdata, UVM_ALL_ON)
        `uvm_field_int(resp,  UVM_ALL_ON)
    `uvm_object_utils_end

  	function new(string name = "axil_csr_tnx");
        super.new(name);
    endfunction

endclass

// =========================================================
// Transaction 2 — Weight tile
// =========================================================

class axis_weight_tnx extends uvm_sequence_item;

    // Flattened 1D — index as w0[r*TB_COLS + c]
    // uvm_field_sarray_int does not support 2D arrays in UVM 1.2
    rand logic signed [W_WIDTH-1:0]   w0   [TB_ROWS*TB_COLS];
    rand logic signed [W_WIDTH-1:0]   w1   [TB_ROWS*TB_COLS];
    rand logic        [IDX_WIDTH-1:0] idx0 [TB_ROWS*TB_COLS];
    rand logic        [IDX_WIDTH-1:0] idx1 [TB_ROWS*TB_COLS];

    rand sparsity_mode_e  sparsity_mode;
    rand logic [3:0]      sparse_mask;

  `uvm_object_utils_begin(axis_weight_tnx)
        `uvm_field_sarray_int(w0, UVM_ALL_ON)
        `uvm_field_sarray_int(w1, UVM_ALL_ON)
        `uvm_field_sarray_int(idx0,UVM_ALL_ON)
        `uvm_field_sarray_int(idx1, UVM_ALL_ON)
        `uvm_field_enum(sparsity_mode_e, sparsity_mode, UVM_ALL_ON)
  		`uvm_field_int(sparse_mask, UVM_ALL_ON)
    `uvm_object_utils_end

    function new(string name = "axis_weight_txn");
        super.new(name);
    endfunction

    // idx0 and idx1 must differ per PE
    constraint c_idx_unique {
        foreach(idx0[i]) idx0[i] != idx1[i];
    }

    // 1:4 mode — w1 must be zero for all PEs
    constraint c_1_4_sparsity {
        if (sparsity_mode == SPARSITY_1_4)
            foreach(w1[i]) w1[i] == 8'sd0;
    }

endclass



// =========================================================
// Transaction 3 — Activation vector
// =========================================================

class axis_act_tnx extends uvm_sequence_item;
  
  
  rand logic signed [A_WIDTH-1:0] a0;
  rand logic signed [A_WIDTH-1:0] a1;
  rand logic signed [A_WIDTH-1:0] a2;
  rand logic signed [A_WIDTH-1:0] a3;
  logic is_last;
  logic mode_dense;
  
  `uvm_object_utils_begin(axis_act_tnx)
    `uvm_field_int(a0,UVM_ALL_ON)
    `uvm_field_int(a1,UVM_ALL_ON)
    `uvm_field_int(a2,UVM_ALL_ON)
    `uvm_field_int(a3,UVM_ALL_ON)
    `uvm_field_int(is_last,UVM_ALL_ON)
    `uvm_field_int(mode_dense,UVM_ALL_ON)
  `uvm_object_utils_end
  
  
  function new(string inst = "axis_act_tnx");
    
    super.new(inst);
    
  endfunction
  
  
  
endclass


// =========================================================
// Transaction 4 — Result vector
// =========================================================

class axis_result_tnx extends uvm_sequence_item;
  
  logic signed [ACC_WIDTH-1:0] result [TB_COLS];
  logic is_last;
  
  
  `uvm_object_utils_begin(axis_result_tnx)
    `uvm_field_sarray_int(result,UVM_ALL_ON)
    `uvm_field_int(is_last,UVM_ALL_ON)
  `uvm_object_utils_end
  
  
  function new(string inst = "axis_result_tnx");
    
    super.new(inst);
    
  endfunction
  
endclass


`endif