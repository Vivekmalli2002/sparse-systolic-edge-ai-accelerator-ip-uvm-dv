# ============================================================
# run.do — Aldec Riviera-PRO regression with coverage merge
# ============================================================

set tests {
    test_065_fsm_error_state_dense
    test_066_fsm_error_state_sparse
    test_075_high_coverage_closure
}

file mkdir results
file mkdir coverage

set pass_count  0
set fail_count  0
set result_lines {}
set acdb_files  {}   ;# list of per-test acdb files to merge

foreach test $tests {

    set logfile  "results/${test}.log"
    set acdb_out "coverage/${test}.acdb"

    # -- run simulation --
    # acdb_output saves THIS test's coverage before fcover.acdb is overwritten
    if {[catch {
        vsim -c work.tb_top \
             +access +r \
             +UVM_TESTNAME=$test \
             +UVM_VERBOSITY=UVM_NONE \
             +UVM_MAX_QUIT_COUNT=1,YES \
             -acdb_file $acdb_out \
             -l $logfile
        run -all
        quit -sim
    } err]} {
        lappend result_lines "FAIL  $test  (sim launch error)"
        incr fail_count
        continue
    }

    # -- save acdb path for merge later --
    if {[file exists $acdb_out]} {
        lappend acdb_files $acdb_out
    }

    # -- parse log --
    set pass_found  0
    set error_found 0
    set fatal_found 0

    if {[catch {open $logfile r} fid]} {
        lappend result_lines "FAIL  $test  (log not found)"
        incr fail_count
        continue
    }

    while {[gets $fid line] >= 0} {
        if {[string match "*TEST PASSED*"  $line]} { set pass_found  1 }
        if {[regexp {UVM_ERROR [^:]} $line]}       { set error_found 1 }
        if {[regexp {UVM_FATAL [^:]} $line]}       { set fatal_found 1 }
    }
    close $fid

    if {$fatal_found || $error_found} {
        incr fail_count
        lappend result_lines "FAIL  $test"
    } elseif {$pass_found} {
        incr pass_count
        lappend result_lines "PASS  $test"
    } else {
        incr fail_count
        lappend result_lines "FAIL  $test  (no PASS marker)"
    }
}

# -----------------------------------------------
# Regression summary
# -----------------------------------------------
set total [expr {$pass_count + $fail_count}]

puts "========================================="
puts "         REGRESSION COMPLETE             "
puts "========================================="
foreach line $result_lines {
    puts "  $line"
}
puts "-----------------------------------------"
puts "  PASSED : $pass_count / $total"
puts "  FAILED : $fail_count / $total"
puts "========================================="

# -----------------------------------------------
# Merge all coverage databases
# -----------------------------------------------
if {[llength $acdb_files] > 0} {

    puts ""
    puts "========================================="
    puts "  Merging Coverage ([llength $acdb_files] tests)"
    puts "========================================="

    # ✅ Correct Aldec acdb merge syntax: -i per file, -o for output
    set merge_cmd "acdb merge -o coverage/merged.acdb"
    foreach f $acdb_files {
        append merge_cmd " -i $f"
    }

    if {[catch {eval $merge_cmd} err]} {
        puts "WARN: Merge failed: $err"
    } else {
        puts "Merged OK: coverage/merged.acdb"

        # ✅ Correct Aldec report syntax
        if {[catch {
            acdb report -i coverage/merged.acdb -o coverage/merged_report.txt -txt
        } err]} {
            puts "WARN: Report failed: $err"
            puts "Try opening coverage/merged.acdb in Aldec GUI manually"
        } else {
            # Print report to console
            if {[catch {open coverage/merged_report.txt r} fid]} {
                puts "Could not read report file"
            } else {
                puts ""
                puts "========================================="
                puts "     OVERALL COVERAGE SUMMARY            "
                puts "========================================="
                while {[gets $fid line] >= 0} {
                    puts $line
                }
                close $fid
                puts "========================================="
            }
        }
    }

} else {
    puts "No coverage databases found to merge"
}