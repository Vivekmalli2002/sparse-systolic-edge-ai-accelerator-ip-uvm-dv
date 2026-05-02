// =============================================================================
// File: 01_pkg_v18.sv
// Description: V18 Unified Package - Merged V16 Compute + V17 Data Path
// Version: 18.4 - 128-bit AXI-Stream for improved throughput
// =============================================================================
// Merge Strategy:
//   - V16: Sparsity modes, PE power states, ECC, debug trace, watchdog params
//   - V17: AXI4-Stream parameters, credit-based flow control, CSR map
//   - V18: TUSER sparsity metadata for streaming sparse weights
//   - V18.1: Post-processing unit parameters, AXI-Lite interface support
//   - V18.4: Widened AXI-Stream from 64 to 128 bits for 2x throughput
// =============================================================================

`timescale 1ns/1ps

// =============================================================================
// PACKAGE: accel_pkg_v18
// =============================================================================
package accel_pkg_v18;

    // =========================================================================
    // Version Information
    // =========================================================================
    localparam logic [7:0]  IP_VERSION_MAJOR = 8'd18;
    localparam logic [7:0]  IP_VERSION_MINOR = 8'd4;  // V18.4: 128-bit AXI
    localparam logic [15:0] IP_VERSION_PATCH = 16'h0000;
    localparam logic [31:0] IP_VERSION = {IP_VERSION_MAJOR, IP_VERSION_MINOR, IP_VERSION_PATCH};

    // =========================================================================
    // Array Configuration (From V16)
    // =========================================================================
    localparam int ROWS       = 8;
    localparam int COLS       = 8;
    localparam int ARRAY_SIZE = 8;   // Alias for compatibility
    localparam int PE_STAGES  = 2;   // Pipeline stages in PE MAC
    
    // =========================================================================
    // Data Widths (From V16)
    // =========================================================================
    localparam int W_WIDTH    = 8;   // Weight width
    localparam int A_WIDTH    = 8;   // Activation width
    localparam int ACC_WIDTH  = 32;  // Accumulator width (expanded from V16's 24)
    localparam int IDX_WIDTH  = 2;   // Sparse index width for 2:4
    
    // Derived packet widths
    localparam int WGT_PKT_WIDTH = (2*W_WIDTH) + (2*IDX_WIDTH);  // 20 bits: 2 weights + 2 indices
    localparam int ACT_PKT_WIDTH = 4*A_WIDTH;                     // 32 bits: 4 activations

    // =========================================================================
    // AXI4-Stream Configuration (V18.4: Widened to 128-bit)
    // =========================================================================
    localparam int AXIS_DATA_WIDTH    = 128;                         // 128-bit TDATA (was 64)
    localparam int AXIS_KEEP_WIDTH    = AXIS_DATA_WIDTH / 8;         // 16-bit TKEEP (was 8)
    localparam int AXIS_ID_WIDTH      = 4;                           // TID width
    localparam int AXIS_DEST_WIDTH    = 4;                           // TDEST width
    localparam int AXIS_USER_WIDTH    = 8;                           // TUSER for sparsity metadata
    
    // Per-interface FIFO depths
    localparam int WEIGHT_FIFO_DEPTH  = 16;
    localparam int ACT_FIFO_DEPTH     = 16;
    localparam int RESULT_FIFO_DEPTH  = 32;
    
    // Credit-based flow control (From V17)
    localparam int WEIGHT_FIFO_CREDITS = WEIGHT_FIFO_DEPTH - 2;  // Leave headroom
    localparam int ACT_FIFO_CREDITS    = ACT_FIFO_DEPTH - 2;

    // =========================================================================
    // AXI4-Lite Configuration (Updated for RISC-V Integration)
    // =========================================================================
    localparam int AXIL_ADDR_WIDTH = 12;   // 4KB CSR space
    localparam int AXIL_DATA_WIDTH = 32;   // 32-bit registers
    localparam int AXIL_STRB_WIDTH = AXIL_DATA_WIDTH / 8;
    
    // AXI-Lite response codes
    localparam logic [1:0] AXIL_RESP_OKAY   = 2'b00;
    localparam logic [1:0] AXIL_RESP_EXOKAY = 2'b01;
    localparam logic [1:0] AXIL_RESP_SLVERR = 2'b10;
    localparam logic [1:0] AXIL_RESP_DECERR = 2'b11;

    // =========================================================================
    // AXI4 Full Configuration (From V16 - for DMA)
    // =========================================================================
    localparam int AXI_ADDR_WIDTH    = 32;
    localparam int AXI_DATA_WIDTH    = 128;  // Widened to match AXIS
    localparam int AXI_ID_WIDTH      = 4;
    localparam int AXI_STRB_WIDTH    = AXI_DATA_WIDTH / 8;
    localparam int AXI_MAX_BURST_LEN = 256;

    // =========================================================================
    // Buffer Configuration (From V16)
    // =========================================================================
    localparam int UBUF_BANKS      = 4;
    localparam int UBUF_BANK_DEPTH = 2048;
    localparam int UBUF_DATA_WIDTH = 128;  // Widened to match AXIS
    localparam int UBUF_ADDR_WIDTH = $clog2(UBUF_BANK_DEPTH);
    
    localparam int WFIFO_DEPTH       = 8;    // Weight tile FIFO (2x for performance)
    localparam int OUTPUT_FIFO_DEPTH = 512;  // Output staging FIFO (8x - PERFORMANCE OPTIMIZED!)

    // =========================================================================
    // Skid Buffer Configuration (From V17)
    // =========================================================================
    localparam int SKID_DEPTH = 2;  // 2-entry elastic buffer

    // =========================================================================
    // ECC Configuration (From V16)
    // =========================================================================
    localparam int ECC_WIDTH   = 8;   // SECDED for 64-bit data
    localparam bit ENABLE_ECC  = 1;

    // =========================================================================
    // Debug Trace Configuration (From V16)
    // =========================================================================
    localparam int TRACE_DEPTH = 256;
    localparam int TRACE_WIDTH = 128;
    localparam bit ENABLE_DEBUG_TRACE = 1;

    // =========================================================================
    // Watchdog Configuration (From V16)
    // =========================================================================
    localparam int WATCHDOG_WIDTH  = 32;
    localparam bit ENABLE_WATCHDOG = 1;

    // =========================================================================
    // Performance Counter Configuration (From V17)
    // =========================================================================
    localparam int PERF_CNT_WIDTH = 32;
    localparam int NUM_PERF_COUNTERS = 8;

    // =========================================================================
    // Post-Processing Configuration (NEW for V18.1)
    // =========================================================================
    localparam int PP_BIAS_WIDTH   = 16;   // Per-channel bias width
    localparam int PP_SCALE_WIDTH  = 16;   // Multiplier scale width
    localparam int PP_SHIFT_WIDTH  = 6;    // Right-shift amount (0-63)
    localparam int PP_PIPELINE_STAGES = 3; // Bias → Scale → Shift+Sat

    // =========================================================================
    // Sparsity Mode Enumeration (From V16)
    // =========================================================================
    typedef enum logic [1:0] {
        SPARSITY_DENSE = 2'b00,   // No sparsity, process all weights
        SPARSITY_2_4   = 2'b01,   // 2:4 structured sparsity (50% sparse)
        SPARSITY_1_4   = 2'b10,   // 1:4 structured sparsity (75% sparse)
        SPARSITY_4_8   = 2'b11    // 4:8 structured sparsity (50% sparse, larger block)
    } sparsity_mode_e;

    // =========================================================================
    // TUSER Sparsity Metadata (NEW for V18)
    // Description: Carried on AXI-Stream TUSER for weight interface
    // =========================================================================
    typedef struct packed {
        logic [3:0] sparse_mask;    // 4-bit mask: which of 4 weights are non-zero
        logic [1:0] sparsity_mode;  // Maps to sparsity_mode_e
        logic       last_in_tile;   // Last weight group in current tile
        logic       valid;          // Metadata valid flag
    } weight_tuser_t;               // Total: 8 bits = AXIS_USER_WIDTH

    // =========================================================================
    // PE Power State Enumeration (From V16)
    // =========================================================================
    typedef enum logic [1:0] {
        PE_ACTIVE     = 2'b00,   // Fully operational
        PE_IDLE       = 2'b01,   // Idle, ready to activate
        PE_CLOCK_GATE = 2'b10,   // Clock gated for power saving
        PE_POWER_DOWN = 2'b11    // Full power down (retention optional)
    } pe_power_state_e;

    // =========================================================================
    // Activation Function Enumeration (Merged V16 + V17)
    // =========================================================================
    typedef enum logic [2:0] {
        ACT_NONE       = 3'b000,  // Bypass (linear)
        ACT_RELU       = 3'b001,  // max(0, x)
        ACT_RELU6      = 3'b010,  // min(max(0, x), 6)
        ACT_LEAKY_RELU = 3'b011,  // x if x > 0 else alpha*x
        ACT_SIGMOID    = 3'b100,  // 1/(1+e^-x) - LUT based
        ACT_TANH       = 3'b101   // tanh(x) - LUT based
    } activation_e;

    // =========================================================================
    // Post-Processing Operation Enumeration (NEW for V18.1)
    // =========================================================================
    typedef enum logic [2:0] {
        PP_NONE        = 3'b000,  // Bypass (no post-processing)
        PP_BIAS_ADD    = 3'b001,  // Add per-channel bias only
        PP_SCALE_SHIFT = 3'b010,  // Multiply by scale, then shift
        PP_REQUANT     = 3'b011,  // Full requantization: bias + scale + shift + zero_point
        PP_BIAS_SCALE  = 3'b100   // Bias add followed by scale+shift
    } postproc_op_e;

    // =========================================================================
    // Compute Controller States (Merged V16 + V17)
    // =========================================================================
    typedef enum logic [2:0] {
        S_IDLE         = 3'b000,  // Waiting for start
        S_LOAD_WEIGHTS = 3'b001,  // Loading weights into array
        S_STREAM       = 3'b010,  // Streaming activations, computing
        S_DRAIN        = 3'b011,  // Draining results from array
        S_DONE         = 3'b100,  // Computation complete
        S_ERROR        = 3'b101,  // Error state
        S_RECOVERY     = 3'b110   // Recovering from error
    } compute_state_e;

    // =========================================================================
    // DMA Target Enumeration (From V16)
    // =========================================================================
    typedef enum logic [2:0] {
        DMA_TARGET_UBUF_ACT = 3'b000,  // Activations to unified buffer
        DMA_TARGET_UBUF_RES = 3'b001,  // Results from unified buffer
        DMA_TARGET_WFIFO    = 3'b010,  // Weights to weight FIFO
        DMA_TARGET_DEBUG    = 3'b011   // Debug trace readout
    } dma_target_e;

    // =========================================================================
    // DMA States (From V16)
    // =========================================================================
    typedef enum logic [2:0] {
        DMA_IDLE  = 3'b000,
        DMA_ADDR  = 3'b001,
        DMA_READ  = 3'b010,
        DMA_WRITE = 3'b011,
        DMA_RESP  = 3'b100,
        DMA_DONE  = 3'b101,
        DMA_ERROR = 3'b110
    } dma_state_e;

    // =========================================================================
    // Result TX Arbitration States (From V17)
    // =========================================================================
    typedef enum logic [1:0] {
        TX_IDLE   = 2'b00,
        TX_SEND   = 2'b01,
        TX_PAUSE  = 2'b10
    } tx_state_e;

    // =========================================================================
    // ECC Error Structure (From V16)
    // =========================================================================
    typedef struct packed {
        logic        correctable;
        logic        uncorrectable;
        logic [12:0] error_addr;
        logic [1:0]  error_bank;
    } ecc_error_t;

    // =========================================================================
    // IRQ Sources (Merged V16 + V17)
    // =========================================================================
    localparam int IRQ_COMPUTE_DONE   = 0;
    localparam int IRQ_DMA_DONE       = 1;
    localparam int IRQ_DMA_ERROR      = 2;
    localparam int IRQ_OVERFLOW       = 3;
    localparam int IRQ_UNDERFLOW      = 4;   // New: Stream underflow
    localparam int IRQ_ECC_CORR       = 5;   // ECC correctable
    localparam int IRQ_ECC_UNCORR     = 6;   // ECC uncorrectable
    localparam int IRQ_WATCHDOG       = 7;   // Watchdog timeout
    localparam int NUM_IRQ_SOURCES    = 8;

    // =========================================================================
    // CSR Address Map (Merged V16 + V17, Reorganized)
    // =========================================================================
    
    // ----- Basic Control (0x000 - 0x00F) -----
    localparam logic [11:0] CSR_CTRL        = 12'h000;  // Control register
    localparam logic [11:0] CSR_STATUS      = 12'h004;  // Status register
    localparam logic [11:0] CSR_TILE_CFG    = 12'h008;  // Tile configuration (M, N, K dims)
    localparam logic [11:0] CSR_SPARSITY    = 12'h00C;  // Sparsity mode config
    
    // ----- IRQ Configuration (0x010 - 0x01F) -----
    localparam logic [11:0] CSR_IRQ_EN      = 12'h010;  // IRQ enable mask
    localparam logic [11:0] CSR_IRQ_STATUS  = 12'h014;  // IRQ status (W1C)
    localparam logic [11:0] CSR_IRQ_FORCE   = 12'h018;  // Force IRQ for test
    
    // ----- AXI-Stream Config (0x020 - 0x02F) - NEW for V18 -----
    localparam logic [11:0] CSR_AXIS_WFIFO  = 12'h020;  // Weight FIFO status/credits
    localparam logic [11:0] CSR_AXIS_AFIFO  = 12'h024;  // Activation FIFO status
    localparam logic [11:0] CSR_AXIS_RFIFO  = 12'h028;  // Result FIFO status
    localparam logic [11:0] CSR_AXIS_CTRL   = 12'h02C;  // Stream control
    
    // ----- Performance Counters (0x030 - 0x04F) -----
    localparam logic [11:0] CSR_PERF_CYCLES = 12'h030;  // Total cycles
    localparam logic [11:0] CSR_PERF_STALL  = 12'h034;  // Stall cycles
    localparam logic [11:0] CSR_PERF_MAC    = 12'h038;  // MAC operations
    localparam logic [11:0] CSR_PERF_ZW     = 12'h03C;  // Zero weight skips
    localparam logic [11:0] CSR_PERF_ZA     = 12'h040;  // Zero activation skips
    localparam logic [11:0] CSR_PERF_UTIL   = 12'h044;  // PE utilization
    localparam logic [11:0] CSR_PERF_BW_RD  = 12'h048;  // Read bandwidth
    localparam logic [11:0] CSR_PERF_BW_WR  = 12'h04C;  // Write bandwidth
    
    // ----- Watchdog (0x050 - 0x05F) -----
    localparam logic [11:0] CSR_WDOG_CFG    = 12'h050;  // Watchdog config
    localparam logic [11:0] CSR_WDOG_STATUS = 12'h054;  // Watchdog status
    
    // ----- ECC (0x060 - 0x06F) -----
    localparam logic [11:0] CSR_ECC_CFG     = 12'h060;  // ECC config
    localparam logic [11:0] CSR_ECC_STATUS  = 12'h064;  // ECC status
    localparam logic [11:0] CSR_ECC_INJECT  = 12'h068;  // Error injection
    localparam logic [11:0] CSR_ECC_ADDR    = 12'h06C;  // Error address
    
    // ----- Debug Trace (0x070 - 0x07F) -----
    localparam logic [11:0] CSR_DBG_CTRL    = 12'h070;  // Debug control
    localparam logic [11:0] CSR_DBG_STATUS  = 12'h074;  // Debug status
    localparam logic [11:0] CSR_DBG_TRIG_MSK= 12'h078;  // Trigger mask
    localparam logic [11:0] CSR_DBG_TRIG_VAL= 12'h07C;  // Trigger value
    
    // ----- Power Management (0x080 - 0x08F) -----
    localparam logic [11:0] CSR_PWR_CFG     = 12'h080;  // Power config
    localparam logic [11:0] CSR_PWR_STATUS  = 12'h084;  // Power status
    
    // ----- DMA Configuration (0x090 - 0x09F) -----
    localparam logic [11:0] CSR_DMA_SRC     = 12'h090;  // DMA source address
    localparam logic [11:0] CSR_DMA_DST     = 12'h094;  // DMA destination address
    localparam logic [11:0] CSR_DMA_CFG     = 12'h098;  // DMA config (len, direction)
    localparam logic [11:0] CSR_DMA_STATUS  = 12'h09C;  // DMA status
    
    // ----- Activation Function (0x0A0 - 0x0AF) -----
    localparam logic [11:0] CSR_ACT_CFG     = 12'h0A0;  // Activation function select
    localparam logic [11:0] CSR_ACT_PARAM   = 12'h0A4;  // Activation parameters (e.g., leaky alpha)
    
    // ----- Post-Processing (0x0B0 - 0x0CF) - NEW for V18.1 -----
    localparam logic [11:0] CSR_PP_CTRL     = 12'h0B0;  // Post-proc control: op_sel, round_en, sat_en
    localparam logic [11:0] CSR_PP_SCALE    = 12'h0B4;  // Scale multiplier
    localparam logic [11:0] CSR_PP_SHIFT    = 12'h0B8;  // Right-shift amount
    localparam logic [11:0] CSR_PP_SAT_MAX  = 12'h0BC;  // Saturation maximum
    localparam logic [11:0] CSR_PP_SAT_MIN  = 12'h0C0;  // Saturation minimum (was CSR_PP_BIAS_0)
    localparam logic [11:0] CSR_PP_BIAS_0   = 12'h0C4;  // Bias[1:0] - packed 2x16-bit
    localparam logic [11:0] CSR_PP_BIAS_1   = 12'h0C8;  // Bias[3:2]
    localparam logic [11:0] CSR_PP_BIAS_2   = 12'h0CC;  // Bias[5:4]
    localparam logic [11:0] CSR_PP_BIAS_3   = 12'h0D0;  // Bias[7:6]
    localparam logic [11:0] CSR_PP_BIAS_4   = 12'h0D4;  // Bias[9:8]
    localparam logic [11:0] CSR_PP_BIAS_5   = 12'h0D8;  // Bias[11:10]
    localparam logic [11:0] CSR_PP_BIAS_6   = 12'h0DC;  // Bias[13:12]
    localparam logic [11:0] CSR_PP_BIAS_7   = 12'h0E0;  // Bias[15:14]
    // ----- Weight Reuse Configuration (0x0E4) - NEW for V18.2 -----
    // [31:16] = act_tile_count: Number of activation tiles per weight load
    // [15:0]  = reserved (default act_tile_count=1 for backwards compatibility)
    localparam logic [11:0] CSR_ACT_TILE_CFG = 12'h0E4;
    
    // ----- Scalable Bias Memory (0x0E8-0x0EC) - NEW for V18.3 -----
    // Supports any array size up to 256 columns
    localparam logic [11:0] CSR_PP_BIAS_ADDR = 12'h0E8;  // [7:0] = column index for next write
    localparam logic [11:0] CSR_PP_BIAS_DATA = 12'h0EC;  // [15:0] = bias value, auto-increments addr
    
    localparam logic [11:0] CSR_PP_ZP_0     = 12'h0D4;  // Zero points[3:0] - packed 4x8-bit (requant)
    localparam logic [11:0] CSR_PP_ZP_1     = 12'h0D8;  // Zero points[7:4]
    
    // ----- Capability/Version (0x0F0 - 0x0FF) -----
    localparam logic [11:0] CSR_CAP0        = 12'h0F0;  // Capability 0: array size, sparsity modes
    localparam logic [11:0] CSR_CAP1        = 12'h0F4;  // Capability 1: buffer sizes
    localparam logic [11:0] CSR_CAP2        = 12'h0F8;  // Capability 2: features (ECC, debug, etc)
    localparam logic [11:0] CSR_VERSION     = 12'h0FC;  // IP Version

    // =========================================================================
    // CSR Bit Field Definitions
    // =========================================================================
    
    // CSR_CTRL bit fields
    localparam int CTRL_ENABLE_BIT    = 0;   // Global enable
    localparam int CTRL_START_BIT     = 1;   // Start computation (self-clearing)
    localparam int CTRL_SOFT_RST_BIT  = 2;   // Soft reset
    localparam int CTRL_DMA_START_BIT = 3;   // Start DMA (self-clearing)
    localparam int CTRL_ABORT_BIT     = 4;   // Abort current operation
    localparam int CTRL_ERR_CLR_BIT   = 5;   // Clear error state
    localparam int CTRL_FLUSH_BIT     = 6;   // Flush all FIFOs
    
    // CSR_STATUS bit fields
    localparam int STAT_BUSY_BIT      = 0;   // Computation in progress
    localparam int STAT_DONE_BIT      = 1;   // Computation complete
    localparam int STAT_ERROR_BIT     = 2;   // Error occurred
    localparam int STAT_WFIFO_RDY_BIT = 3;   // Weight FIFO ready
    localparam int STAT_AFIFO_RDY_BIT = 4;   // Activation FIFO ready
    localparam int STAT_RFIFO_RDY_BIT = 5;   // Result FIFO has data
    localparam int STAT_STATE_LSB     = 8;   // Current FSM state [10:8]
    localparam int STAT_STATE_MSB     = 10;
    
    // CSR_TILE_CFG bit fields
    localparam int TILE_M_LSB         = 0;   // M dimension [7:0]
    localparam int TILE_M_MSB         = 7;
    localparam int TILE_N_LSB         = 8;   // N dimension [15:8]
    localparam int TILE_N_MSB         = 15;
    localparam int TILE_K_LSB         = 16;  // K dimension [23:16]
    localparam int TILE_K_MSB         = 23;
    
    // CSR_SPARSITY bit fields
    localparam int SPARSE_MODE_LSB    = 0;   // Sparsity mode [1:0]
    localparam int SPARSE_MODE_MSB    = 1;
    localparam int SPARSE_EN_BIT      = 2;   // Enable sparse processing
    localparam int SPARSE_SKIP_ZA_BIT = 3;   // Skip zero activations
    
    // CSR_DMA_CFG bit fields
    localparam int DMA_CFG_LEN_LSB    = 0;   // Transfer length [15:0]
    localparam int DMA_CFG_LEN_MSB    = 15;
    localparam int DMA_CFG_WRITE_BIT  = 16;  // 1=write, 0=read
    localparam int DMA_CFG_TGT_LSB    = 17;  // Target select [19:17]
    localparam int DMA_CFG_TGT_MSB    = 19;
    
    // CSR_WDOG_CFG bit fields
    localparam int WDOG_EN_BIT        = 0;   // Watchdog enable
    localparam int WDOG_AUTO_RST_BIT  = 1;   // Auto-reset on timeout
    localparam int WDOG_TIMEOUT_LSB   = 8;   // Timeout value [31:8]
    localparam int WDOG_TIMEOUT_MSB   = 31;
    
    // CSR_ECC_CFG bit fields
    localparam int ECC_EN_BIT         = 0;   // ECC enable
    localparam int ECC_CORR_EN_BIT    = 1;   // Enable correction
    localparam int ECC_INJ_EN_BIT     = 2;   // Enable error injection

    // CSR_PP_CTRL bit fields
    localparam int PP_OP_LSB          = 0;   // Post-proc operation [2:0]
    localparam int PP_OP_MSB          = 2;
    localparam int PP_ROUND_EN_BIT    = 8;   // Enable rounding before shift
    localparam int PP_SAT_EN_BIT      = 9;   // Enable saturation
    localparam int PP_BYPASS_ACT_BIT  = 10;  // Bypass activation function (use PP only)
    localparam int PP_PER_CH_SCALE_BIT= 11;  // Enable per-channel scale (requant mode)

    // =========================================================================
    // Capability Register Definitions
    // =========================================================================
    
    // CAP0: Array configuration
    // [7:0]   = ROWS
    // [15:8]  = COLS
    // [17:16] = Sparsity modes supported (bit mask)
    // [23:18] = Reserved
    // [31:24] = PE pipeline stages
    localparam logic [31:0] CAP0_VALUE = {
        8'(PE_STAGES),           // [31:24]
        6'b0,                    // [23:18]
        2'b11,                   // [17:16] Dense + 2:4 supported
        8'(COLS),                // [15:8]
        8'(ROWS)                 // [7:0]
    };
    
    // CAP1: Buffer sizes
    // [7:0]   = Weight FIFO depth
    // [15:8]  = Activation FIFO depth
    // [23:16] = Result FIFO depth
    // [31:24] = Weight tile buffer depth
    localparam logic [31:0] CAP1_VALUE_PKG = {
        8'(WFIFO_DEPTH),         // [31:24]
        8'(RESULT_FIFO_DEPTH),   // [23:16]
        8'(ACT_FIFO_DEPTH),      // [15:8]
        8'(WEIGHT_FIFO_DEPTH)    // [7:0]
    };
    
    // CAP2: Features
    // [0]  = ECC supported
    // [1]  = Debug trace supported
    // [2]  = Watchdog supported
    // [3]  = Clock gating supported
    // [4]  = Sparsity supported
    // [5]  = Post-processing supported
    // [6]  = 128-bit AXI supported (V18.4)
    // [7]  = Reserved
    localparam logic [31:0] CAP2_VALUE = {
        24'b0,
        1'b1,                    // [7] Reserved
        1'b1,                    // [6] 128-bit AXI
        1'b1,                    // [5] Post-processing
        1'b1,                    // [4] Sparsity
        1'b1,                    // [3] Clock gating
        1'b1,                    // [2] Watchdog
        1'b1,                    // [1] Debug trace
        1'b1                     // [0] ECC
    };

    // =========================================================================
    // Weight Stream Payload (128-bit TDATA interpretation) - V18.4 Updated
    // 6 weight packets per beat (128/20 = 6, with 8 bits unused)
    // =========================================================================
    typedef struct packed {
        logic [7:0]           reserved;     // [127:120] unused bits
        logic [W_WIDTH-1:0]   weight1_5;    // [119:112]
        logic [W_WIDTH-1:0]   weight0_5;    // [111:104]
        logic [IDX_WIDTH-1:0] index1_5;     // [103:102]
        logic [IDX_WIDTH-1:0] index0_5;     // [101:100]
        logic [W_WIDTH-1:0]   weight1_4;    // [99:92]
        logic [W_WIDTH-1:0]   weight0_4;    // [91:84]
        logic [IDX_WIDTH-1:0] index1_4;     // [83:82]
        logic [IDX_WIDTH-1:0] index0_4;     // [81:80]
        logic [W_WIDTH-1:0]   weight1_3;    // [79:72]
        logic [W_WIDTH-1:0]   weight0_3;    // [71:64]
        logic [IDX_WIDTH-1:0] index1_3;     // [63:62]
        logic [IDX_WIDTH-1:0] index0_3;     // [61:60]
        logic [W_WIDTH-1:0]   weight1_2;    // [59:52]
        logic [W_WIDTH-1:0]   weight0_2;    // [51:44]
        logic [IDX_WIDTH-1:0] index1_2;     // [43:42]
        logic [IDX_WIDTH-1:0] index0_2;     // [41:40]
        logic [W_WIDTH-1:0]   weight1_1;    // [39:32]
        logic [W_WIDTH-1:0]   weight0_1;    // [31:24]
        logic [IDX_WIDTH-1:0] index1_1;     // [23:22]
        logic [IDX_WIDTH-1:0] index0_1;     // [21:20]
        logic [W_WIDTH-1:0]   weight1_0;    // [19:12]
        logic [W_WIDTH-1:0]   weight0_0;    // [11:4]
        logic [IDX_WIDTH-1:0] index1_0;     // [3:2]
        logic [IDX_WIDTH-1:0] index0_0;     // [1:0]
    } weight_stream_128_t;  // Maps to 128-bit TDATA
    
    // =========================================================================
    // Activation Stream Payload (128-bit TDATA interpretation) - V18.4 Updated
    // 16 activations packed per beat
    // =========================================================================
    typedef struct packed {
        logic [A_WIDTH-1:0] act15;  // [127:120]
        logic [A_WIDTH-1:0] act14;  // [119:112]
        logic [A_WIDTH-1:0] act13;  // [111:104]
        logic [A_WIDTH-1:0] act12;  // [103:96]
        logic [A_WIDTH-1:0] act11;  // [95:88]
        logic [A_WIDTH-1:0] act10;  // [87:80]
        logic [A_WIDTH-1:0] act9;   // [79:72]
        logic [A_WIDTH-1:0] act8;   // [71:64]
        logic [A_WIDTH-1:0] act7;   // [63:56]
        logic [A_WIDTH-1:0] act6;   // [55:48]
        logic [A_WIDTH-1:0] act5;   // [47:40]
        logic [A_WIDTH-1:0] act4;   // [39:32]
        logic [A_WIDTH-1:0] act3;   // [31:24]
        logic [A_WIDTH-1:0] act2;   // [23:16]
        logic [A_WIDTH-1:0] act1;   // [15:8]
        logic [A_WIDTH-1:0] act0;   // [7:0]
    } activation_stream_128_t;  // Maps to 128-bit TDATA
    
    // =========================================================================
    // Result Stream Payload (128-bit TDATA interpretation) - V18.4 Updated
    // 4 x 32-bit accumulators per beat
    // =========================================================================
    typedef struct packed {
        logic [ACC_WIDTH-1:0] result3;  // [127:96]
        logic [ACC_WIDTH-1:0] result2;  // [95:64]
        logic [ACC_WIDTH-1:0] result1;  // [63:32]
        logic [ACC_WIDTH-1:0] result0;  // [31:0]
    } result_stream_128_t;  // Maps to 128-bit TDATA

endpackage


// =============================================================================
// PACKAGE: axis_pkg_v18
// Description: AXI4-Stream interface type definitions
// =============================================================================
package axis_pkg_v18;
    
    import accel_pkg_v18::*;
    
    // =========================================================================
    // AXI4-Stream Master Interface (128-bit) - V18.4 Updated
    // =========================================================================
    typedef struct packed {
        logic [AXIS_DATA_WIDTH-1:0]   tdata;
        logic [AXIS_KEEP_WIDTH-1:0]   tkeep;
        logic                         tlast;
        logic [AXIS_ID_WIDTH-1:0]     tid;
        logic [AXIS_DEST_WIDTH-1:0]   tdest;
        logic [AXIS_USER_WIDTH-1:0]   tuser;
        logic                         tvalid;
    } axis_m_t;
    
    typedef struct packed {
        logic                         tready;
    } axis_s_t;
    
    // =========================================================================
    // Weight Stream Interface (128-bit) - V18.4 Updated
    // =========================================================================
    typedef struct packed {
        logic [AXIS_DATA_WIDTH-1:0]   tdata;
        logic [AXIS_KEEP_WIDTH-1:0]   tkeep;
        logic                         tlast;
        logic [AXIS_USER_WIDTH-1:0]   tuser;   // Sparsity metadata
        logic                         tvalid;
    } axis_weight_m_t;
    
    // =========================================================================
    // Activation Stream Interface (128-bit) - V18.4 Updated
    // =========================================================================
    typedef struct packed {
        logic [AXIS_DATA_WIDTH-1:0]   tdata;
        logic [AXIS_KEEP_WIDTH-1:0]   tkeep;
        logic                         tlast;
        logic                         tvalid;
    } axis_act_m_t;
    
    // =========================================================================
    // Result Stream Interface (128-bit) - V18.4 Updated
    // =========================================================================
    typedef struct packed {
        logic [AXIS_DATA_WIDTH-1:0]   tdata;
        logic [AXIS_KEEP_WIDTH-1:0]   tkeep;
        logic                         tlast;
        logic [AXIS_USER_WIDTH-1:0]   tuser;
        logic                         tvalid;
    } axis_result_m_t;

endpackage


// =============================================================================
// PACKAGE: axil_pkg_v18
// Description: AXI4-Lite interface type definitions (NEW for V18.1)
// =============================================================================
package axil_pkg_v18;
    
    import accel_pkg_v18::*;
    
    // =========================================================================
    // AXI4-Lite Write Address Channel
    // =========================================================================
    typedef struct packed {
        logic [AXIL_ADDR_WIDTH-1:0] awaddr;
        logic [2:0]                  awprot;
        logic                        awvalid;
    } axil_aw_m_t;
    
    typedef struct packed {
        logic                        awready;
    } axil_aw_s_t;
    
    // =========================================================================
    // AXI4-Lite Write Data Channel
    // =========================================================================
    typedef struct packed {
        logic [AXIL_DATA_WIDTH-1:0] wdata;
        logic [AXIL_STRB_WIDTH-1:0] wstrb;
        logic                        wvalid;
    } axil_w_m_t;
    
    typedef struct packed {
        logic                        wready;
    } axil_w_s_t;
    
    // =========================================================================
    // AXI4-Lite Write Response Channel
    // =========================================================================
    typedef struct packed {
        logic [1:0]                  bresp;
        logic                        bvalid;
    } axil_b_s_t;
    
    typedef struct packed {
        logic                        bready;
    } axil_b_m_t;
    
    // =========================================================================
    // AXI4-Lite Read Address Channel
    // =========================================================================
    typedef struct packed {
        logic [AXIL_ADDR_WIDTH-1:0] araddr;
        logic [2:0]                  arprot;
        logic                        arvalid;
    } axil_ar_m_t;
    
    typedef struct packed {
        logic                        arready;
    } axil_ar_s_t;
    
    // =========================================================================
    // AXI4-Lite Read Data Channel
    // =========================================================================
    typedef struct packed {
        logic [AXIL_DATA_WIDTH-1:0] rdata;
        logic [1:0]                  rresp;
        logic                        rvalid;
    } axil_r_s_t;
    
    typedef struct packed {
        logic                        rready;
    } axil_r_m_t;
    
    // =========================================================================
    // Combined AXI4-Lite Master Interface (from master perspective)
    // =========================================================================
    typedef struct packed {
        axil_aw_m_t aw;
        axil_w_m_t  w;
        axil_b_m_t  b;
        axil_ar_m_t ar;
        axil_r_m_t  r;
    } axil_master_t;
    
    // =========================================================================
    // Combined AXI4-Lite Slave Interface (from slave perspective)
    // =========================================================================
    typedef struct packed {
        axil_aw_s_t aw;
        axil_w_s_t  w;
        axil_b_s_t  b;
        axil_ar_s_t ar;
        axil_r_s_t  r;
    } axil_slave_t;

endpackage


// =============================================================================
// Include RTL modules (kept for file organization)
// =============================================================================
// Note: When using this package standalone, comment out these includes
// and compile modules separately
 `include "02_core_and_array_v18.sv"
 `include "03_buffers_v18.sv"
 `include "04_axis_interfaces_v18.sv"
 `include "05_control_v18.sv"
 `include "06_top_v18.sv"
 `include "07_postproc_v18.sv"


// =============================================================================
// Compile Check: Import packages
// =============================================================================
module pkg_compile_check;
    import accel_pkg_v18::*;
    import axis_pkg_v18::*;
    import axil_pkg_v18::*;
    
    // Verify key parameters
    initial begin
        assert(ROWS == 8) else $error("ROWS mismatch");
        assert(COLS == 8) else $error("COLS mismatch");
        assert(AXIS_DATA_WIDTH == 128) else $error("AXIS width mismatch - expected 128");
        assert(AXIS_KEEP_WIDTH == 16) else $error("AXIS_KEEP_WIDTH mismatch - expected 16");
        assert(AXIS_USER_WIDTH == 8) else $error("TUSER width mismatch");
        assert(AXIL_DATA_WIDTH == 32) else $error("AXIL width mismatch");
        assert(PP_BIAS_WIDTH == 16) else $error("PP_BIAS_WIDTH mismatch");
        $display("V18.4 Package compile check PASSED (128-bit AXI)");
        $display("  IP Version: %0d.%0d", IP_VERSION_MAJOR, IP_VERSION_MINOR);
        $display("  Array: %0dx%0d", ROWS, COLS);
        $display("  Data: W=%0d, A=%0d, ACC=%0d", W_WIDTH, A_WIDTH, ACC_WIDTH);
        $display("  AXI-Stream: TDATA=%0d, TKEEP=%0d, TUSER=%0d", AXIS_DATA_WIDTH, AXIS_KEEP_WIDTH, AXIS_USER_WIDTH);
        $display("  AXI-Lite: ADDR=%0d, DATA=%0d", AXIL_ADDR_WIDTH, AXIL_DATA_WIDTH);
        $display("  Post-Proc: BIAS_W=%0d, SCALE_W=%0d, SHIFT_W=%0d", 
                 PP_BIAS_WIDTH, PP_SCALE_WIDTH, PP_SHIFT_WIDTH);
    end
endmodule