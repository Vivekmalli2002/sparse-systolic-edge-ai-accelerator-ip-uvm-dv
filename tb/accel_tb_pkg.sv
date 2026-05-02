`ifndef ACCEL_TB_PKG_SV
`define ACCEL_TB_PKG_SV

package accel_tb_pkg;

    // =====================================================
    // CHANGE ONLY THESE TWO TO RESIZE ENTIRE TESTBENCH
    // Must match ROWS_P and COLS_P in tb_top.sv
    // =====================================================
    parameter int TB_ROWS = 16;
    parameter int TB_COLS = 16;
    localparam int OFIFO_DEPTH = 256;

    // Timing
    parameter int CLK_PERIOD_NS   = 5;
    parameter int RESET_CYCLES    = 20;
    parameter int TIMEOUT_CYCLES  = 100_000;
    parameter int PIPELINE_LATENCY = 48;  // cycles from last act to first result

    // Derived packing parameters — follow automatically
    parameter int TB_PKTS_PER_BEAT   = 128 / 20;
    parameter int TB_BEATS_PER_ROW   = (TB_COLS + TB_PKTS_PER_BEAT - 1)
                                        / TB_PKTS_PER_BEAT;
    parameter int TB_BEATS_PER_TILE  = TB_ROWS * TB_BEATS_PER_ROW;
    parameter int TB_RESULTS_PER_BEAT = 128 / 32;
    parameter int TB_RESULT_BEATS    = (TB_COLS + TB_RESULTS_PER_BEAT - 1)
                                        / TB_RESULTS_PER_BEAT;

   
    // =========================================================================
    // Performance calculations
    // =========================================================================
    localparam real CLK_FREQ_MHZ = 200.0;
    localparam real CLK_FREQ_GHZ = CLK_FREQ_MHZ / 1000.0;                 // 0.2 GHz
    // Your dual‑MAC PE equals two TPU‑style MAC units (2 multiply‑accumulate pairs)
    localparam int  PEAK_MACS_PER_CYCLE = 2 * TB_ROWS * TB_COLS;         // 512
    localparam real PEAK_GMACS          = PEAK_MACS_PER_CYCLE * CLK_FREQ_GHZ; // 102.4 GMACS


endpackage

`endif