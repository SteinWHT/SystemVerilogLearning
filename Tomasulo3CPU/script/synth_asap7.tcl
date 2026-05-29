# synth_asap7.tcl - Design Compiler synthesis for Tomasulo3CPU using ASAP7
#
# Default top is CPU.
#
# Usage:
#   dc_shell -f synth_asap7.tcl
#   dc_shell -x "set argv {CPU 3.0}" -f synth_asap7.tcl
#
# Important:
#   ASAP7 Liberty files use time_unit : "1ps" internally. This script resets
#   the design/SDC units to ns/uW after linking, so constraints and reports use
#   the same user-facing units as standard flows.

# ==========================================================================
# 0. Argument Parsing
# ==========================================================================
if { [info exists argv] && [llength $argv] > 0 } {
    set TOP_DESIGN [lindex $argv 0]
} else {
    set TOP_DESIGN "CPU"
}

if { [info exists argv] && [llength $argv] > 1 } {
    set CLK_PERIOD [lindex $argv 1]
} else {
    set CLK_PERIOD 3.0
}
set CLK_PERIOD_PS [expr {$CLK_PERIOD * 1000.0}]

echo "Top-Level Design : $TOP_DESIGN"
echo "Target Technology: ASAP7 7nm Predictive PDK (RVT, TT corner)"
echo "Clock Period     : $CLK_PERIOD ns"

proc write_ns_timing_report {raw_file ns_file} {
    set in_path 0
    set fin [open $raw_file r]
    set fout [open $ns_file w]

    puts $fout "NOTE: ASAP7 Liberty timing units are ps. Numeric timing columns in this report"
    puts $fout "      have been divided by 1000 and are shown in ns for comparison."
    puts $fout ""

    while { [gets $fin line] >= 0 } {
        if { [regexp {^\s*Point\s+Incr\s+Path\s*$} $line] } {
            set in_path 1
            puts $fout "  Point                                                   Incr(ns)   Path(ns)"
            continue
        }

        if { $in_path && [regexp {^\s*$} $line] } {
            set in_path 0
            puts $fout $line
            continue
        }

        if { $in_path } {
            if { [regexp {^(.*\S)\s+([-+]?[0-9]+\.?[0-9]*)\s+([-+]?[0-9]+\.?[0-9]*)(\s+[rf])$} $line -> prefix n1 n2 suffix] } {
                puts $fout [format "%s %10.4f %10.4f%s" $prefix [expr {$n1 / 1000.0}] [expr {$n2 / 1000.0}] $suffix]
            } elseif { [regexp {^(.*\S)\s+([-+]?[0-9]+\.?[0-9]*)\s+([-+]?[0-9]+\.?[0-9]*)?$} $line -> prefix n1 n2] } {
                if { $n2 eq "" } {
                    puts $fout [format "%s %10.4f" $prefix [expr {$n1 / 1000.0}]]
                } else {
                    puts $fout [format "%s %10.4f %10.4f" $prefix [expr {$n1 / 1000.0}] [expr {$n2 / 1000.0}]]
                }
            } elseif { [regexp {^(.*\S)\s+([-+]?[0-9]+\.?[0-9]*)$} $line -> prefix n1] } {
                puts $fout [format "%s %10.4f" $prefix [expr {$n1 / 1000.0}]]
            } else {
                puts $fout $line
            }
        } else {
            puts $fout $line
        }
    }

    close $fin
    close $fout
}

# ==========================================================================
# 1. Path Setup
# ==========================================================================
set _script [info script]
if { $_script eq "" } {
    set SCRIPT_DIR [pwd]
} else {
    set SCRIPT_DIR [file dirname [file normalize $_script]]
}
set PROJ_DIR [file normalize [file join $SCRIPT_DIR ".."]]

set SRC_DIR "$PROJ_DIR/src"
set RPT_DIR "$PROJ_DIR/report"
set SYN_DIR "$PROJ_DIR/synth"

file mkdir $RPT_DIR
file mkdir $SYN_DIR

echo "Project Root : $PROJ_DIR"
echo "Source Dir   : $SRC_DIR"
echo "Report Dir   : $RPT_DIR"
echo "Synth Dir    : $SYN_DIR"

# ==========================================================================
# 2. Library Setup
# ==========================================================================
set lib_dir "/data/asap7_lib"
set db_files [glob -nocomplain "$lib_dir/*RVT_TT*nldm*.db"]

set required_groups {AO INVBUF OA SEQ SIMPLE}
set missing {}
foreach grp $required_groups {
    set found 0
    foreach db $db_files {
        if { [string match "*${grp}*" $db] } { set found 1; break }
    }
    if { !$found } { lappend missing $grp }
}

if { [llength $missing] > 0 } {
    echo "================================================================"
    echo " ERROR: Missing ASAP7 .db files for cell groups:"
    foreach m $missing { echo "   $m" }
    echo ""
    echo " Build the libraries first with Library Compiler."
    echo "================================================================"
    exit 1
}

set target_library $db_files
set link_library   [concat "*" $db_files "dw_foundation.sldb"]
set search_path    [list . $lib_dir $SRC_DIR "$SRC_DIR/simple_module" "$SRC_DIR/back_end" "$SRC_DIR/back_end/ISSUE_QUEUE" "$SRC_DIR/back_end/EXE" $SYN_DIR]

echo "Using ASAP7 libraries:"
foreach db $db_files { echo "  $db" }

# ==========================================================================
# 3. Read RTL
# ==========================================================================
set WORK_DIR "$SYN_DIR/WORK_ASAP7"
file mkdir $WORK_DIR
define_design_lib WORK -path $WORK_DIR
define_name_rules verilog -allowed "a-z A-Z 0-9 _" -first_restricted "0-9"

# SystemVerilog files in correct package-first dependency order
set src_files [list \
    "$SRC_DIR/riscv_funct_pkg.sv" \
    "$SRC_DIR/riscv_opcode_pkg.sv" \
    "$SRC_DIR/riscv_types_pkg.sv" \
    "$SRC_DIR/simple_module/sync_fifo.sv" \
    "$SRC_DIR/simple_module/dual_port_memory.sv" \
    "$SRC_DIR/simple_module/sync_lifo.sv" \
    "$SRC_DIR/IFQ.sv" \
    "$SRC_DIR/BPB.sv" \
    "$SRC_DIR/RAS.sv" \
    "$SRC_DIR/FRL.sv" \
    "$SRC_DIR/FRAT.sv" \
    "$SRC_DIR/ROB.sv" \
    "$SRC_DIR/RBA.sv" \
    "$SRC_DIR/RRAT.sv" \
    "$SRC_DIR/SB.sv" \
    "$SRC_DIR/RISC_V_DECODER.sv" \
    "$SRC_DIR/DISPATCH.sv" \
    "$SRC_DIR/CPU_FRONT_END.sv" \
    "$SRC_DIR/back_end/ISSUE_QUEUE/INTQ.sv" \
    "$SRC_DIR/back_end/ISSUE_QUEUE/MULQ.sv" \
    "$SRC_DIR/back_end/ISSUE_QUEUE/DIVQ.sv" \
    "$SRC_DIR/back_end/ISSUE_QUEUE/LSQ.sv" \
    "$SRC_DIR/back_end/ISSUE_QUEUE/ISSUEQ.sv" \
    "$SRC_DIR/back_end/LSB.sv" \
    "$SRC_DIR/back_end/ISSUEUNIT.sv" \
    "$SRC_DIR/back_end/PRF.sv" \
    "$SRC_DIR/back_end/EXE/ALU.sv" \
    "$SRC_DIR/back_end/EXE/DIV.sv" \
    "$SRC_DIR/back_end/EXE/MUL.sv" \
    "$SRC_DIR/back_end/EXE/EXE.sv" \
    "$SRC_DIR/back_end/CDB.sv" \
    "$SRC_DIR/back_end/CPU_BACK_END.sv" \
    "$SRC_DIR/CSR.sv" \
    "$SRC_DIR/CPU.sv" \
]

foreach f $src_files {
    if { ![file exists $f] } {
        echo "Error: Required RTL file missing: $f"
        exit 1
    }
}

echo "Analyzing RTL (SystemVerilog)..."
analyze -format sverilog $src_files
elaborate $TOP_DESIGN
current_design $TOP_DESIGN
uniquify
link

# Use ns/uW reporting and SDC units, even though ASAP7 Liberty data is stored
# with ps/pW library units internally.
set_units -time ns -resistance kOhm -capacitance fF -voltage V -current mA -power uW
report_units > "$RPT_DIR/${TOP_DESIGN}_asap7_units.txt"

# ==========================================================================
# 4. Check Design
# ==========================================================================
echo "Running check_design..."
set check_ok [check_design]
check_design > "$RPT_DIR/${TOP_DESIGN}_asap7_check_design.txt"
if { $check_ok != 1 } {
    echo "WARNING: check_design reported issues. See $RPT_DIR/${TOP_DESIGN}_asap7_check_design.txt"
}

# ==========================================================================
# 5. Constraints
# ==========================================================================
set clk_coll [get_ports clk -filter "direction==in"]
if { [sizeof_collection $clk_coll] > 0 } {
    create_clock -name clk -period $CLK_PERIOD_PS [get_ports clk]
    set all_in_ex_clk [remove_from_collection [all_inputs] [get_ports clk]]
    set_input_delay  [expr {$CLK_PERIOD_PS * 0.20}] -clock clk $all_in_ex_clk
    set_output_delay [expr {$CLK_PERIOD_PS * 0.20}] -clock clk [all_outputs]
} else {
    echo "Warning: clk port not found; no clock constraint applied."
}

set rst_coll [get_ports rst_n -filter "direction==in"]
if { [sizeof_collection $rst_coll] > 0 } {
    set_ideal_network [get_ports rst_n]
}

set_wire_load_mode top

# ==========================================================================
# 6. Synthesize
# ==========================================================================
echo "Starting ASAP7 synthesis..."
compile -exact_map

# ==========================================================================
# 7. Reports
# ==========================================================================
echo "Writing reports..."
report_timing -max_paths 20 > "$RPT_DIR/${TOP_DESIGN}_asap7_timing_raw_ps.txt"
write_ns_timing_report "$RPT_DIR/${TOP_DESIGN}_asap7_timing_raw_ps.txt" "$RPT_DIR/${TOP_DESIGN}_asap7_timing.txt"
report_area                 > "$RPT_DIR/${TOP_DESIGN}_asap7_area.txt"
report_power                > "$RPT_DIR/${TOP_DESIGN}_asap7_power.txt"
report_qor                  > "$RPT_DIR/${TOP_DESIGN}_asap7_qor.txt"
report_reference            > "$RPT_DIR/${TOP_DESIGN}_asap7_reference.txt"

# ==========================================================================
# 8. Outputs
# ==========================================================================
change_names -rules verilog -hierarchy
write -format verilog -hierarchy -output "$SYN_DIR/${TOP_DESIGN}_asap7_mapped.v"
write_sdc "$SYN_DIR/${TOP_DESIGN}_asap7_mapped.sdc"

echo "Synthesis of $TOP_DESIGN on ASAP7 complete."
exit
