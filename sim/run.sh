cat > sim/run.sh << 'EOF'
#!/bin/bash
# run.sh — compile and simulate V18 UVM TB
# Usage: ./sim/run.sh [test_name]
# Example: ./sim/run.sh accel_sanity_test

TEST=${1:-accel_sanity_test}
echo "Running test: $TEST"

vlib work

vlog -timescale 1ns/1ns \
     -sv \
     +incdir+$RIVIERA_HOME/vlib/uvm-1.2/src \
     -l uvm_1_2 \
     +access+rw \
     ./rtl/01_pkg_v18.sv \
     ./rtl/02_core_and_array_v18.sv \
     ./rtl/03_buffers_v18.sv \
     ./rtl/04_axis_interfaces_v18.sv \
     ./rtl/05_control_v18.sv \
     ./rtl/07_postproc_v18.sv \
     ./rtl/06_top_v18.sv \
     ./tb/testbench.sv

vsim -c \
     +access+rw \
     +UVM_TESTNAME=$TEST \
     -do "run -all; exit"
EOF

chmod +x sim/run.sh