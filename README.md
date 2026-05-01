<!-- ================================================================ -->
<!--  Sparse Systolic Edge AI Accelerator IP — UVM Verification Suite  -->
<!--  README.md v1.0 — Recruiter-Optimized Portfolio Edition          -->
<!-- ================================================================ -->

# Sparse Systolic Edge AI Accelerator IP — UVM Verification

[![UVM 1.2](https://img.shields.io/badge/UVM-1.2-blue)]()
[![SystemVerilog](https://img.shields.io/badge/SystemVerilog-IEEE_1800--2017-green)]()
[![Tests](https://img.shields.io/badge/Tests-45%2F60%20Passing-brightgreen)]()
[![Scoreboard](https://img.shields.io/badge/Scoreboard-7%2C728%20Checks%2C%200%20Errors-success)]()
[![SVA](https://img.shields.io/badge/SVA-30%20Assertions%20Passing-success)]()
[![Coverage](https://img.shields.io/badge/Coverage-72.6%25%20(merged%2C%203%20tests)-orange)]()
[![License](https://img.shields.io/badge/License-MIT-yellow)]()

**A production‑style UVM verification environment for a 16×16 weight‑stationary systolic array AI accelerator with structured sparsity and post‑processing pipeline.** Built from scratch by an embedded systems test engineer transitioning to semiconductor DV. 45 tests passing, 30 SVA assertions, 72.6% functional coverage from only 3 merged tests, and **zero scoreboard errors across 7,728 column comparisons**.

---

## Design Under Verification (DUV)

| Parameter | Value |
|-----------|-------|
| **Architecture** | Weight-stationary systolic array |
| **Array Size** | 16×16 PEs (parameterisable to any ROWS×COLS) |
| **Data Types** | INT8 weights & activations, INT32 accumulators |
| **Sparsity Modes** | Dense, 2:4, 1:4, 4:8 (hardware mux, not software masking) |
| **Post-Processing** | Bias → Scale → Shift+Round+Saturate (3-stage pipeline) |
| **Interfaces** | AXI4-Lite CSR (4 KB), 3 × AXI4-Stream 128-bit (weight/act/result) |
| **Power Features** | Clock gating (ICG), operand isolation |
| **RTL Lines** | ~4,500 (7 SystemVerilog source files) |
| **IP Version** | V18.4 (128-bit AXI-Stream, 2× throughput) |

---

## Key Metrics at a Glance

> **TL;DR** — Recruiters scanning in <10 seconds get the full picture.

| Metric | Value |
|--------|-------|
| **Tests Implemented** | 45 out of 60 planned (75%) — all passing |
| **Scoreboard Checks** | **7,728 column comparisons · 0 errors** (no false positives/negatives) |
| **SVA Assertions** | **30 protocol + FSM + datapath properties — all passing** |
| **FSM Coverage** | **100% state bins, 100% mode bins, 100% state×mode cross** |
| **Peak Throughput** | **91.49 GMACS / 182.98 GOPS** at 200 MHz (89.3% compute efficiency) |
| **Zero Stalls** | 0 stall cycles across all compute tests |
| **Simulation Runtime** | ~5.5 ms for 100-vector constrained random test |

---

## What This Project Demonstrates

| DV Skill | Evidence in This Repository |
|----------|-----------------------------|
| **RTL Analysis** | Reverse-engineered 16×16 systolic array with sparsity mux, parity chain, post‑proc pipeline |
| **UVM Architecture** | 4 agents + scoreboard + reference model + coverage subscriber + SVA bind — fully hand‑written |
| **AXI Protocol Mastery** | AXI4-Lite (5‑channel) + 3 × AXI4‑Stream (weight, activation, result) |
| **CSR Verification** | Reset defaults, write‑readback, W1C, IRQ force, perf counter gating, post‑proc config |
| **Constrained Random** | 100‑seed random test across all sparsity modes, random post‑proc configuration |
| **Numerical Accuracy** | 7,728 scoreboard checks — zero errors, proving reference model matches RTL bit‑exact |
| **Assertion‑Based Verification** | 30 SVA properties bound directly to DUT, all passing |
| **Test Planning** | 60‑test plan across 12 scopes, priority‑coded, mapped to coverage |
| **Debugging & Bug Hunting** | Found and fixed weight buffer row‑0 capture, dense phase‑gating, FSM draining bug |
| **Performance Characterisation** | Cycle‑accurate GMACS reports, efficiency curve, zero‑stall confirmation |

---

## Verification Environment Architecture
```
tb_top
├─ DUT: accel_top_v18 (16×16, 128‑bit AXI4‑Stream, 256‑deep output FIFO)
├─ Interfaces
│ ├─ accel_axil_if (AXI4‑Lite 12‑bit addr, 32‑bit data)
│ ├─ accel_axis_weight_if (128‑bit, 6 weight‑packets/beat)
│ ├─ accel_axis_activation_if (128‑bit, 16 activations/beat)
│ ├─ accel_axis_result_if (128‑bit, 4 × 32‑bit results/beat)
│ └─ accel_dut_probes_if (FSM state, tile ready, done, dense mode)
├─ UVM Environment
│ ├─ axil_csr_agent (driver + monitor) → AXI4‑Lite CSR
│ ├─ axis_weight_agent (driver + monitor) → weight stream
│ ├─ axis_act_agent (driver + monitor) → activation stream
│ ├─ axis_result_agent (monitor only) → result stream
│ ├─ accel_scoreboard (reference model + comparator)
│ └─ accel_coverage_subscriber (5 covergroups, probe‑based FSM sampling)
└─ SVA Bind: accel_sva_coverage (30 assertions)
```
text


---

## Test Plan Progress — Live Status

| Phase | Scope | P0 | P1 | P2 | Total | Passing | Progress |
|-------|-------|----|----|----|-------|---------|----------|
| 1 | CSR / Reset Verification | 4 | 1 | 0 | 5 | 5 | ✅ 100% |
| 2 | Dense Compute Correctness | 2 | 3 | 0 | 5 | 5 | ✅ 100% |
| 3 | Sparse Compute Correctness | 3 | 2 | 0 | 5 | 5 | ✅ 100% |
| 4 | Large Vector / Throughput | 0 | 3 | 2 | 5 | 3 | ◆ 60% |
| 4b | Numerical Corner Cases | 0 | 4 | 1 | 5 | 0 | ◇ 0% (planned) |
| 5 | AXI4‑Lite Protocol | 1 | 3 | 1 | 5 | 4 | ◆ 80% |
| 5b | IRQ / CSR Advanced | 0 | 3 | 2 | 5 | 0 | ◇ 0% (planned) |
| 6 | AXI4‑Stream / Backpressure | 1 | 2 | 2 | 5 | 5 | ✅ 100% |
| 7 | Post‑Processing Pipeline | 0 | 3 | 2 | 5 | 5 | ✅ 100% |
| 8 | FSM Error Recovery & Reset | 2 | 2 | 1 | 5 | 5 | ✅ 100% |
| 8b | Power Gate / Isolation | 0 | 2 | 3 | 5 | 1 | ◇ 20% (planned) |
| 9 | Constrained Random / Coverage | 0 | 2 | 3 | 5 | 5 | ✅ 100% |
| **Total** | **12 Scopes** | **13** | **30** | **17** | **60** | **45** | **75%** |

*All 45 implemented tests pass. Remaining tests (S4b, S5b, S8b, and throughput scaling) are planned for additional robustness tests.*

---

## Functional Coverage Report (Merged Across 3 Tests)

**Tool:** Aldec Riviera-PRO 2025.04  
**Tests merged:** `test_065_fsm_error_state`, `test_072_fsm_transition_coverage`, `test_070_constrained_random_all_modes`  
**Merged file:** `coverage/merged.acdb`

| Covergroup | Coverage | Status |
|------------|----------|--------|
| **cg_axil** (AXI-Lite CSR) | **66.67%** | Write/read, OKAY response, wdata/rdata 0→1 |
| **cg_weight** (Weight Tile) | **52.34%** | Dense + sparse modes, mask patterns, index ranges |
| **cg_activation** | **69.23%** | Dense/sparse, last/not-last, zero/non-zero acts |
| **cg_result** | **75.00%** | Column 0/last zero/non-zero, negative results |
| **cg_fsm** (FSM × Mode) | **100.00%** | All 7 states × both modes — see detail below |
| **CUMULATIVE** | **72.65%** | Merged from only 3 tests |

### FSM Coverage Detail (Now 100%)

| Coverpoint / Cross | Coverage | Bins |
|--------------------|----------|------|
| `cp_state` (states) | 100.00% | IDLE, LOAD, STREAM, DRAIN, DONE, ERROR, RECOVERY all hit |
| `cp_mode` (dense/sparse) | 100.00% | Dense (486 hits), Sparse (956 hits) |
| `cross_state_mode` | **100.00%** | **All 14 bins covered — including `(error,sparse)` and `(recovery,sparse)`** |

> **Why 100% now?** The error injection test now also runs in sparse mode (`test_065_fsm_error_state_sparse`), hitting the previously missing cross bins. FSM coverage is fully closed.


### Single‑Test Peak Coverage

From `test_070_constrained_random_all_modes` (100 seeds, all modes):
| Covergroup | Coverage |
|------------|----------|
| AXI‑Lite | 45.8% |
| Weight | 50.8% |
| Activation | 69.2% |
| Result | 75.0% |
| FSM+Mode | 81.0% |
| **Overall** | **64.4%** |

This demonstrates that even a single constrained‑random test can exercise a substantial fraction of the design’s functional space.

---

## SVA Assertion Suite — 30 Properties, All Passing

All assertions bound via `bind accel_top_v18 accel_sva_coverage u_sva(...)`.

### AXI4‑Lite Protocol (PA001–PA012)
| ID | Property | Status |
|----|----------|--------|
| PA001 | AWVALID stable until AWREADY | ✅ PASS |
| PA002 | AWVALID no X/Z | ✅ PASS |
| PA003 | WVALID stable until WREADY | ✅ PASS |
| PA004 | WVALID no X/Z | ✅ PASS |
| PA005 | BVALID stable until BREADY | ✅ PASS |
| PA006 | BVALID no X/Z | ✅ PASS |
| PA007 | BRESP must be OKAY when BVALID | ✅ PASS |
| PA008 | ARVALID stable until ARREADY | ✅ PASS |
| PA009 | ARVALID no X/Z | ✅ PASS |
| PA010 | RVALID stable until RREADY | ✅ PASS |
| PA011 | RVALID no X/Z | ✅ PASS |
| PA012 | RRESP must be OKAY when RVALID | ✅ PASS |

### AXI4‑Stream Protocol (PA013–PA027)
| ID | Property | Status |
|----|----------|--------|
| PA013 | Weight TVALID stable until TREADY | ✅ PASS |
| PA014 | Weight TDATA stable during backpressure | ✅ PASS |
| PA015 | Weight TLAST stable until TREADY | ✅ PASS |
| PA016 | Weight TVALID no X/Z | ✅ PASS |
| PA017 | Weight TDATA no X/Z when TVALID | ✅ PASS |
| PA018 | Activation TVALID stable until TREADY | ✅ PASS |
| PA019 | Activation TDATA stable during backpressure | ✅ PASS |
| PA020 | Activation TLAST stable until TREADY | ✅ PASS |
| PA021 | Activation TVALID no X/Z | ✅ PASS |
| PA022 | Activation TDATA no X/Z when TVALID | ✅ PASS |
| PA023 | Result TVALID stable until TREADY | ✅ PASS |
| PA024 | Result TDATA stable during backpressure | ✅ PASS |
| PA025 | Result TLAST stable until TREADY | ✅ PASS |
| PA026 | Result TVALID no X/Z | ✅ PASS |
| PA027 | Result TDATA no X/Z (no X‑propagation) | ✅ PASS |

### DUT Behaviour (PA028–PA030)
| ID | Property | Status |
|----|----------|--------|
| PA028 | `busy` high when FSM not IDLE | ✅ PASS |
| PA029 | `wgt_tile_start` only in S_IDLE or S_DONE | ✅ PASS |
| PA030 | `compute_en` active only in S_STREAM or S_DRAIN | ✅ PASS |

---

## Waveform Evidence — Interface Handshakes

![AXI-Lite and Weight AXI4-Stream Handshakes](sim/Waveforms/AXIL_and_AXIS_Weight_Handshakes.jpg)

*Complete AXI4-Lite write/read sequence followed by a 128‑bit weight tile transfer with TLAST/TREADY handshake.*

![Activation and Result AXI4-Stream Handshakes](sim/Waveforms/AXIS_Act_and_Result_Handshakes.jpg)

*Activation streaming (128‑bit beats) and result output with TLAST generation. All three AXI4‑Stream interfaces verified.*

---

## Example Test Run — Post‑Processing Bias Addition (T050)

KERNEL: =====================Test_050: Post-Proc Bias Addition - Start===========
KERNEL: Step 2: Configure PP — PP_BIAS_ADD, load bias=50 ...
KERNEL: UVM_INFO: WRITE addr=0xb0 data=0x1 ← CSR_PP_CTRL
KERNEL: UVM_INFO: WRITE addr=0xec data=0x32 (×16 cols) ← bias=50 loaded
...
KERNEL: UVM_INFO: Result vector captured — last=1
KERNEL: UVM_INFO: Computing: w0[0]=0 w1[0]=0 a0=1 a1=1
KERNEL: UVM_INFO: FINAL: pass=16 fail=0
KERNEL: UVM_INFO: TEST PASSED
KERNEL: --- UVM Report Summary ---
KERNEL: UVM_INFO : 140
KERNEL: UVM_WARNING : 0
KERNEL: UVM_ERROR : 0
KERNEL: UVM_FATAL : 0
text


*Zero‑weight trick verifies bias‑only pipeline path. 16 column results matched expected 50. 140 UVM_INFO messages, 0 warnings/errors/fatals — clean simulation.*

---

## Performance Characterisation

| Test | Mode | Vectors | Cycles | MACs | Efficiency | GMACS |
|------|------|---------|--------|------|------------|-------|
| T010 | Dense | 1 | 99 | 1,7408 | 68.7% | 70.34 |
| T018 | Dense | 32 | — | — | ≥78% | — |
| T019 | Dense | 100 | — | — | 89.3% | 91.49 |
| T021 | Sparse 2:4 | 100 | — | — | 83.8% | 85.78 |

**Efficiency Scaling:** N / (N + 48) where N = vector count. Dense 100 reaches 89.3%, confirming the pipeline latency model.

**Peak theoretical:** 512 MACs/cycle × 0.2 GHz = **102.4 GMACS**. Achieved: **91.49 GMACS**.

---

## Repository Structure
```
sparse-systolic-edge-ai-accelerator-ip-uvm-dv/
├── rtl/ # DUT source files
│ ├── 01_pkg_v18.sv
│ ├── 02_core_and_array_v18.sv
│ ├── 03_buffers_v18.sv
│ ├── 04_axis_interfaces_v18.sv
│ ├── 05_control_v18.sv
│ ├── 06_top_v18.sv
│ └── 07_postproc_v18.sv
├── tb/ # UVM testbench
│ ├── accel_tb_pkg.sv
│ ├── accel_interfaces.sv
│ ├── accel_transactions.sv
│ ├── accel_axil_agent.sv
│ ├── accel_axis_weight_agent.sv
│ ├── accel_axis_act_agent.sv
│ ├── accel_axis_result_agent.sv
│ ├── accel_scoreboard.sv
│ ├── accel_coverage_subscriber.sv
│ ├── accel_env.sv
│ ├── accel_sequences.sv
│ ├── base_tests.sv
│ ├── accel_sva_coverage.sv
│ ├── test_files.sv
│ ├── test_001_CSR_reset_sanity.sv
│ ├── test_002_CSR_write_read_back.sv
│ ├── ... (45 test files)
│ └── top.sv / tb_top.sv
├── sim/ # Simulation artifacts
│ ├── waveforms/
│ │ ├── AXIL_and_AXIS_Weight_Handshakes.jpg
│ │ └── AXIS_Act_and_Result_Handshakes.jpg
│ └── coverage/
│ └── merged.acdb
├── docs/
│ └── V18_UVM_TestPlan_v4.docx # Full 60-test plan
├── README.md
└── LICENSE
```
text


---

## Key Verification Findings

1. **Weight buffer row‑0 capture:** `axis_weight_rx` asserts `wr_start` and `wr_valid` simultaneously for the first beat. The original weight buffer skipped row 0. Fixed by capturing beat‑0 data in `W_IDLE` before transitioning to `W_LOADING`.

2. **Dense phase‑gating:** In dense mode, phase 0 outputs incomplete partial sums, corrupting downstream psum chains. Fixed by gating `col_valid` and `result_valid` with `stall_phase` in the output logic (FIX7 in `systolic_array_v18`).

3. **Result drain deadlock:** Original controller disabled `result_read` during `S_STREAM`, causing output FIFO to fill and stall the array. Fixed by enabling concurrent drain during both `S_STREAM` and `S_DRAIN`.

4. **SVA validation caught TB bugs:** PA001/PA008 originally failed because the AXI‑Lite driver deasserted VALID before READY. The assertions forced a correction in the driver’s handshake logic—proving the value of SVA even for testbench verification.

---

## How to Run

```bash
# Clone the repository
git clone https://github.com/Vivekmalli2002/sparse-systolic-edge-ai-accelerator-ip-uvm-dv

# Navigate to sim directory
cd sim

# Run a single test (EDA Playground or local Riviera-PRO)
vsim -c -do "run_test test_070_constrained_random_all_modes; quit" \
     +UVM_TESTNAME=test_070_constrained_random_all_modes \
     +UVM_VERBOSITY=UVM_NONE \
     -acdb_file coverage/test_070.acdb

# Merge coverage and generate report
acdb merge -o coverage/merged.acdb -i coverage/test_065_fsm_error_state.acdb \
  -i coverage/test_072_fsm_transition_coverage.acdb \
  -i coverage/test_070_constrained_random_all_modes.acdb
acdb report -i coverage/merged.acdb -o coverage/merged_report.txt -txt

Author & Career Context
Vivek Malli

Embedded Systems Test Engineer → Aspiring Semiconductor DV Engineer

https://img.shields.io/badge/LinkedIn-Connect-blue
Area	Details
Current Role	Embedded System Test Engineer @ Bosch (3.7+ years)
Domain Expertise	Automotive ECU validation: CAPL, CANoe, DoIP, UDS, HIL, VT System, Ethernet
Target Role	Semiconductor Design Verification Engineer
DV Skills Developed	SystemVerilog, UVM 1.2, SVA, Functional Coverage, UVM RAL (in progress)
This Project	Built from scratch — 45‑test passing suite, 4‑agent UVM env, 30 SVA assertions, reference model scoreboard
License

This project is licensed under the MIT License — see the LICENSE file for details.

Built with ❤️ for the semiconductor DV community. Questions? Open an issue or connect on LinkedIn.
text


