# Sparse Systolic Edge AI Accelerator IP — UVM DV

> TPU-inspired, silicon-ready sparse AI inference accelerator IP  
> with complete UVM verification environment.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![UVM](https://img.shields.io/badge/UVM-1.2-green.svg)]()
[![SystemVerilog](https://img.shields.io/badge/Language-SystemVerilog-orange.svg)]()
[![Simulator](https://img.shields.io/badge/Simulator-Riviera--PRO%202025.04-purple.svg)]()
[![Tests Passing](https://img.shields.io/badge/Tests%20Passing-26%2F26-brightgreen.svg)]()
[![SVA](https://img.shields.io/badge/SVA%20Assertions-30%20passing-brightgreen.svg)]()
[![Coverage](https://img.shields.io/badge/Per--test%20Coverage-100%25-brightgreen.svg)]()
[![Scoreboard Checks](https://img.shields.io/badge/Scoreboard%20Checks-7%2C728%20pass-brightgreen.svg)]()

---

## What This Project Demonstrates

A **complete, end-to-end Silicon DV project** — not a tutorial clone, not a textbook copy.
Full lifecycle: RTL design archaeology → UVM testbench architecture → test execution → result analysis → progressive closure.

| Skill Area | Evidence in This Project |
|---|---|
| **RTL Understanding** | 16×16 systolic array with sparsity mux, ICG, parity chain, post-processing pipeline |
| **UVM Architecture** | 4 agents + scoreboard + reference model + SVA bind — all hand-written |
| **Protocol Knowledge** | AXI4-Lite 5-channel handshake + 3 × AXI4-Stream (weight / activation / result) |
| **CSR Verification** | Reset defaults, write-readback, W1C, IRQ force, perf counter gating — T001–T005 |
| **Compute Verification** | Dense + all 3 sparse modes × 1/8/100 vectors — T010–T025 |
| **Numerical Accuracy** | 7,728 scoreboard column comparisons across 26 tests — zero errors |
| **Performance Analysis** | Cycle-accurate GMACS reports, efficiency curve, zero-stall confirmation |
| **SVA Assertions** | 30 protocol + FSM + data-path properties bound to DUT |
| **Test Planning** | 63-test plan across 7 groups, progressive P0→P2 priority |

---

## Architecture

![DUT Top-Level Architecture](docs/images/dut_top_architecture.svg)

**Sparsity:** Each `pe_v18` stores `{idx1[1:0], idx0[1:0], w1[7:0], w0[7:0]}`.
In sparse mode, `idx0/idx1` select which of 4 activations each weight multiplies — hardware mux, not software masking.
`isolate_operands` gates the multiplier to zero on zero-weight or zero-activation, cutting dynamic power with no compute loss.

---

## Key Features

### Compute Engine
- **16×16 weight-stationary systolic array** (parameterizable — default RTL 8×8; TB runs 16×16)
- **INT8 × INT8 → INT32** dual-MAC per PE per cycle (512 MACs/cycle peak)
- 2-stage PE pipeline with cycle-accurate skew/deskew alignment
- **128-bit AXI4-Stream** on all data interfaces (V18.4 — 2× bandwidth vs 64-bit)

### Structured Sparsity — Hardware Native

| Mode | Sparsity | Weights per group | Activation selection | Beats/vector |
|---|---|---|---|---|
| **Dense** | 0% | 4 of 4 (2 phases) | Phase 0: a0,a1 · Phase 1: a2,a3 | 2 |
| **2:4** | 50% | 2 of 4 | idx0/idx1 mux per PE | 1 |
| **1:4** | 75% | 1 of 4 | idx0 only · w1 forced 0 | 1 |
| **4:8** | 50% | 4 of 8 | idx0/idx1 both active | 1 |

### Post-Processing Pipeline (3 stages)
- Stage 1: Per-column bias addition (INT16, up to 256 cols via auto-increment CSR)
- Stage 2: Scale multiply (INT16) + configurable right-shift (0–63 bits)
- Stage 3: Optional rounding + saturation clamp (min/max configurable)
- Activation functions: ReLU, ReLU6, Leaky ReLU (α ≈ 0.125)

### SoC Integration
- AXI4-Lite CSR: 4 KB, 12-bit address, RISC-V / ARM compatible
- IRQ controller: 8 sources, per-source enable mask, write-1-to-clear status
- Weight tile prefetch (V18.3) and weight reuse / act_tile_count (V18.2)
- Performance counters: cycles, stalls, MACs, zero-weight skips, zero-act skips

---

## Verification Results

**26 tests · 0 errors · 0 warnings · 100% per-test coverage · 30 SVA assertions passing**

### CSR Tests (T001–T005)

| Test | Description | Checks | Result |
|---|---|---|---|
| **T001** — Reset sanity | 7 CSR reset default values | 7 PASS | ✅ |
| **T002** — Write-readback | 7 registers across 3 groups (compute, IRQ, post-proc) | 7 PASS | ✅ |
| **T003** — Soft reset | CTRL_SOFT_RST_BIT → FSM=S_IDLE, OFIFO clears | — | ✅ |
| **T004** — IRQ sources | Enable, force, verify status, W1C clear, re-check | 3 PASS | ✅ |
| **T005** — Perf counters | Read before/after enable; verify counters gate on ctrl_enable | monitor | ✅ |

**Key findings from CSR tests:**
- `CSR_IRQ_STATUS` resets to `0x18` (not `0x00`) — bits 3+4 fire immediately because both FIFOs initialize empty. Confirmed correct RTL behavior.
- `CSR_VERSION = 0x12040000` decodes as IP_VERSION_MAJOR=18, MINOR=4, PATCH=0 — V18.4 confirmed.
- Post-processing CSRs fully writable: PP_CTRL (op_sel, round_en, sat_en), PP_SCALE, PP_SAT_MAX, PP_SAT_MIN all pass write-readback.

### Dense Mode Tests (T010–T019)

| Test | Vectors | Cycles | Stalls | Efficiency | GMACS | Checks |
|---|---|---|---|---|---|---|
| T010 — All-ones weights | 1 | 93 | 0 | 66.7% | 68.27 | 16 ✅ |
| T011 — Identity weights | 1 | 93 | 0 | 3.2%* | 4.27 | 16 ✅ |
| T012 — Negative weights (−1) | 1 | 93 | 0 | 66.7% | 68.27 | 16 ✅ |
| T013 — Max weights (127) | 1 | 93 | 0 | 66.7% | 68.27 | 16 ✅ |
| T014 — 8 random vectors | 8 | 107 | 0 | 71.0% | 72.73 | 128 ✅ |
| T018 — 32 vectors | 32 | 155 | 0 | 80.0% | 81.92 | 512 ✅ |
| **T019 — 100 vectors** | **100** | **291** | **0** | **89.3%** | **91.49** | **1600 ✅** |

*T011: 3.2% efficiency is correct — identity weights cause 22,320 zero-weight skips detected per cycle by `pe_zero_weight_map`. The hardware `isolate_operands` signal prevents any multiply switching power.

### Sparse Mode Tests (T015–T025)

| Test | Mode | Vectors | Cycles | Efficiency | GMACS | Checks |
|---|---|---|---|---|---|---|
| T015 | 2:4 | 1 | 92 | 66.3% | 67.90 | 16 ✅ |
| T016 | 1:4 | 1 | 92 | 66.3% | 67.90 | 16 ✅ |
| T017 | 4:8 | 1 | 92 | 66.3% | 67.90 | 16 ✅ |
| T020 | 2:4 | 8 | 99 | 68.7% | 70.34 | 128 ✅ |
| T022 | 1:4 | 8 | 99 | 68.7% | 70.34 | 128 ✅ |
| T024 | 4:8 | 8 | 99 | 68.7% | 70.34 | 128 ✅ |
| **T021** | **2:4** | **100** | **191** | **83.8%** | **85.78** | **1600 ✅** |
| **T023** | **1:4** | **100** | **191** | **83.8%** | **85.78** | **1600 ✅** |
| **T025** | **4:8** | **100** | **191** | **83.8%** | **85.78** | **1600 ✅** |

**Scoreboard total: 7,728 column comparisons · 0 errors**

**Peak theoretical: 102.4 GMACS @ 16×16, 200 MHz**

### Why Efficiency Scales With Vector Count

```
Efficiency = N / (N + PIPELINE_LATENCY)
           = 100 / (100 + 48) ≈ 67.6% theoretical

Dense measured:  89.3% at 100 vectors  (pipeline fills over time)
Sparse measured: 83.8% at 100 vectors  (1 beat/vector vs 2 — less filling time)
```

Zero stall cycles across all 26 tests confirms no output FIFO backpressure under current conditions.

---

## UVM Testbench

```
┌──────────────────────────────────────────────────────┐
│                   UVM Environment                     │
│                                                      │
│  axil_csr_agent    weight_agent    act_agent         │
│  drv+mon+seqr     drv+mon+seqr   drv+mon+seqr       │
│       │                 │               │            │
│       └─────────────────┴───────────────┘            │
│                         │                            │
│              ┌──────────▼──────────┐                 │
│              │    accel_scoreboard  │                 │
│              │  CSR map + Y=WX ref  │                 │
│              │  7728 checks · 0 err │                 │
│              └──────────────────────┘                 │
│                                                      │
│  result_agent (passive)    accel_sva_coverage (bind) │
│  7728 result words         30 assertions PA001–PA030  │
└──────────────────────────────────────────────────────┘
```

| Component | File | Role |
|---|---|---|
| AXI-Lite Agent | `accel_axil_agent.sv` | Full 5-channel handshake, reset idle, W/R sequences |
| Weight Agent | `accel_axis_weight_agent.sv` | 128-bit beat packing · TUSER sparsity metadata |
| Activation Agent | `accel_axis_act_agent.sv` | Dense (2 beats) / Sparse (1 beat) mode-aware |
| Result Agent | `accel_axis_result_agent.sv` | Passive monitor · 4×INT32 per 128-bit beat |
| Scoreboard | `accel_scoreboard.sv` | CSR expected-map + `compute_expected(W,X)` reference model |
| Environment | `accel_env.sv` | Wires all agents → scoreboard via analysis ports |
| Sequences | `accel_sequences.sv` | CSR write/read + weight tile + activation stream |
| SVA Module | `accel_sva_coverage.sv` | 30 properties bound via `bind accel_top_v18 ...` |
| Probe Interface | `accel_dut_probes_if` | Exposes `state_q`, `mode_dense` — no hierarchy in UVM |

---

## Test Plan Progress

```
 Phase 1 — CSR/Control   [████████████████████] 5/5   ✅ COMPLETE
 Phase 2 — Dense Compute [████████████████████] 7/7   ✅ COMPLETE
 Phase 3 — Sparse Compute[████████████████████] 9/9   ✅ COMPLETE  (14 test runs)
 Phase 4 — Protocol/AXI  [░░░░░░░░░░░░░░░░░░░░] 0/12  ◆ IN PROGRESS
 Phase 5 — Post-Proc     [░░░░░░░░░░░░░░░░░░░░] 0/10  ⬜ PLANNED
 Phase 6 — Adv Features  [░░░░░░░░░░░░░░░░░░░░] 0/15  ⬜ PLANNED
 Phase 7 — Stress/Corner [░░░░░░░░░░░░░░░░░░░░] 0/14  ⬜ PLANNED

 TOTAL: 21 / 63 tests passing  ██████████░░░░░░░░░░ 41%
```

Full test plan: `docs/V18_UVM_Test_Plan_v2.docx` — 63 tests, 5 sections, color-coded status badges

### Currently Implemented (T001–T025, T018–T019)
- ✅ CSR reset sanity, write-readback, soft reset, IRQ source/mask/W1C, perf counter gating
- ✅ Dense mode: all-ones, identity, negative, max weights, 1/8/32/100 vectors
- ✅ All 3 sparse modes (2:4, 1:4, 4:8) × 1, 8, 100 vectors each
- ✅ Per-test performance report: cycles, stalls, MACs, GMACS, efficiency

### What's Next (◆ IN PROGRESS)
- `T040` — Capability register readback (CSR_CAP0/1/2/VERSION)
- `T041/T042` — AXI-Lite channel independence (AW/W ordering)
- `T045` — Weight stream backpressure (tready de-asserted mid-tile)
- `T046` — Activation stream backpressure (tready toggling)
- `T047` — Result stream TVALID stability and TLAST position

---

## Repository Structure

```
sparse-systolic-edge-ai-accelerator-ip-uvm-dv/
├── rtl/
│   ├── 01_pkg_v18.sv              # Package: all params, enums, structs, CSR map
│   ├── 02_core_and_array_v18.sv   # pe_v18 + systolic array + skew/deskew buffers
│   ├── 03_buffers_v18.sv          # Sync FIFOs, weight tile buffer, skid buffer
│   ├── 04_axis_interfaces_v18.sv  # AXI4-Stream RX/TX modules (128-bit)
│   ├── 05_control_v18.sv          # CSR + compute FSM + IRQ + performance counters
│   ├── 06_top_v18.sv              # Top-level integration (accel_top_v18)
│   └── 07_postproc_v18.sv         # Post-processing pipeline
├── tb/
│   ├── accel_tb_pkg.sv            # TB parameters (TB_ROWS=16, TB_COLS=16)
│   ├── accel_interfaces.sv        # 5 SV interfaces with clocking blocks
│   ├── accel_transactions.sv      # 4 UVM sequence items
│   ├── accel_axil_agent.sv        # AXI-Lite agent (driver + monitor + agent)
│   ├── accel_axis_weight_agent.sv
│   ├── accel_axis_act_agent.sv
│   ├── accel_axis_result_agent.sv
│   ├── accel_scoreboard.sv        # Compute + CSR checker + reference model
│   ├── accel_env.sv
│   ├── accel_sequences.sv
│   ├── accel_sva_coverage.sv      # 30 SVA properties — bound to DUT
│   ├── top.sv                     # tb_top: DUT, config_db, run_test()
│   ├── base_tests.sv
│   └── test_files.sv              # T001–T025 implementations
├── docs/
│   ├── V18_UVM_Test_Plan_v3.docx  # Full 63-test plan with results + roadmap
│   └── DV_Methodology_Guide.docx  # Design archaeology methodology
├── results/                       # Simulation logs T001–T025
└── sim/
    └── run.sh
```

---

## Quick Start

```bash
git clone https://github.com/Vivekmalli2002/sparse-systolic-edge-ai-accelerator-ip-uvm-dv
cd sparse-systolic-edge-ai-accelerator-ip-uvm-dv

# Run T001 — CSR reset sanity (fastest test, ~240 ns sim time)
./sim/run.sh test_001_CSR_reset_sanity
# Expected: FINAL: pass=7 fail=0  |  TEST PASSED

# Run T025 — 4:8 sparse, 100 vectors (most comprehensive compute test)
./sim/run.sh test_025_sparse_4_8_100vectors
# Expected: Achieved GMACS: 85.78  |  FINAL: pass=1600 fail=0  |  TEST PASSED
```

---

## Tools

| Tool | Version |
|---|---|
| Aldec Riviera-PRO | 2025.04 |
| UVM | 1.2 |
| SystemVerilog | IEEE 1800-2017 |

---

## DV Methodology — Design Archaeology

Four steps used to build this testbench:

1. **Read the package first** — understand every enum, localparam, and struct in `01_pkg_v18.sv` before writing a transaction class
2. **Trace the data path on paper** — weight packet format `{idx1,idx0,w1,w0}`, activation mux per sparse mode, psum chain, deskew alignment timing
3. **Build the TB layer by layer** — interfaces → transactions → agents → sequences → env → tests → coverage
4. **Test progressively** — 1 vector first, then 8, then 100; verify the efficiency curve matches theory before adding more tests

The complete methodology is documented in `docs/DV_Methodology_Guide.docx` — applicable to any RTL design project.

---


### Key Verification Findings

> **T001 finding:** `CSR_IRQ_STATUS` reads `0x18` after reset.  
> Root cause: `afifo_empty` (bit 4) and `wfifo_empty` (bit 3) IRQ sources  
> assert immediately after reset because FIFOs initialize empty.  
> Confirmed expected behaviour via RTL analysis.

> **Driver race fix:** Early simulation runs triggered SVA protocol failures  
> (`awvalid`/`arvalid` deasserted before `ready`). The AXI-Lite driver was  
> repaired to use clocking‑block aligned handshakes, eliminating **all**  
> protocol assertion errors. This proves the value of SVA in catching  
> testbench bugs.

---

## Author

**Vivek Malli**
Embedded Validation Engineer → Semiconductor DV Engineer

3.7+ years — Bosch Automotive (CAPL, CANoe, DoIP, UDS, HIL, VT System, Ethernet)
Target: DV Engineer
Skills(developed) : SV, UVM, SVA,functional coverage, python,UVM RAL(on going)


---

*Built from scratch. Every RTL module designed, every testbench component hand-written.*
*Methodology: design archaeology first — understand the hardware before writing a single test.*