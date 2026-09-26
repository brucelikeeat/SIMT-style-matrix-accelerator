# =============================================================================
# run_rng.do — ModelSim script for tausworthe_lfsr_tb
#
# Usage (from anywhere):
#   do [file normalize [file join [file dirname [info script]] run_rng.do]]
# =============================================================================

set SCRIPT_DIR [file dirname [info script]]
set PROJ_ROOT  [file normalize "$SCRIPT_DIR/../.."]
set RTL_DIR    "$PROJ_ROOT/rtl"
set MC_RTL_DIR "$RTL_DIR/mc_pricer"
set TB_DIR     "$SCRIPT_DIR"

cd $TB_DIR
puts "Working dir: [pwd]"

if {[file isdirectory work]} { vdel -lib work -all }
vlib work

puts "Compiling DUT:  $MC_RTL_DIR/tausworthe_lfsr.sv"
vlog -sv "$MC_RTL_DIR/tausworthe_lfsr.sv"

puts "Compiling TB:   $TB_DIR/tausworthe_lfsr_tb.sv"
vlog -sv "$TB_DIR/tausworthe_lfsr_tb.sv"

vsim -voptargs="+acc" work.tausworthe_lfsr_tb

if {![batch_mode]} {
    add wave -divider "Control"
    add wave -position end sim:/tausworthe_lfsr_tb/clk
    add wave -position end sim:/tausworthe_lfsr_tb/rst
    add wave -position end sim:/tausworthe_lfsr_tb/en

    add wave -divider "Uniform output"
    add wave -position end sim:/tausworthe_lfsr_tb/valid_out
    add wave -radix hex -position end sim:/tausworthe_lfsr_tb/rand_out

    add wave -divider "Sub-generator state"
    add wave -radix hex -position end sim:/tausworthe_lfsr_tb/dut/z0
    add wave -radix hex -position end sim:/tausworthe_lfsr_tb/dut/z1
    add wave -radix hex -position end sim:/tausworthe_lfsr_tb/dut/z2
    add wave -radix hex -position end sim:/tausworthe_lfsr_tb/dut/z3
    add wave -radix hex -position end sim:/tausworthe_lfsr_tb/dut/combined

    add wave -divider "Debug"
    add wave -position end sim:/tausworthe_lfsr_tb/errors

    configure wave -timelineunits ns
}

run -all

puts ""
puts "Simulation complete. Browse waveforms or 'quit -f' to exit."
