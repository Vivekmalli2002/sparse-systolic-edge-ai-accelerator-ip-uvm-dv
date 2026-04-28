# ============================================================
# Regression script for Edge AI Accelerator UVM TB
# Portable for Riviera-PRO / QuestaSim on EDA Playground
# ============================================================

# --- List of all UVM test classes ---------------------------
set tests {
    test_001_CSR_reset_sanity
    test_002_CSR_write_read_back
    test_003_CSR_soft_reset
    test_004_CSR_verify_IRQ_source
    test_005_CSR_perf_counters
    test_010_dense_allones
    test_011_dense_identity_weights
    test_012_dense_negative_weights
    test_013_dense_max_weights
    test_014_dense_8vectors
    test_015_sparse_2_4
    test_016_sparse_1_4
    test_017_sparse_4_8
    test_018_dense_32vectors
    test_019_dense_100vectors
    test_020_sparse_2_4_8vectors
    test_021_sparse_2_4_100vectors
    test_022_sparse_1_4_8vectors
    test_023_sparse_1_4_100vectors
    test_024_sparse_4_8_8vectors
    test_025_sparse_4_8_100vectors
}

# --- Set up ------------------------------------------------
file mkdir results
set pass_count 0
set fail_count 0

# No simulator-specific quiet/onbreak/onerror needed.
# If a test hits $fatal, simulation will stop and the Tcl loop continues.

foreach test $tests {
    set logfile "results/${test}.log"
    puts "========================================="
    puts " Running $test"
    puts "========================================="

    # Start simulation (with read access for SVA/DUT probes)
    vsim -c work.tb_top +access +r +UVM_TESTNAME=$test -l $logfile

    # Run until UVM stops (all objections dropped or $finish)
    run -all
    quit -sim

    # Check result
    if {[catch {exec grep "TEST PASSED" $logfile}]} {
        puts "    ? FAIL (no PASS marker)"
        incr fail_count
    } else {
        if {[catch {exec grep -E "UVM_ERROR|UVM_FATAL" $logfile}]} {
            puts "    ✓ PASS"
            incr pass_count
        } else {
            puts "    ✗ FAIL (errors found)"
            incr fail_count
        }
    }
}

# --- Final summary -----------------------------------------
puts "========================================="
puts " Regression complete"
puts " PASS: $pass_count"
puts " FAIL: $fail_count"
puts " Logs saved in results/"
puts "========================================="