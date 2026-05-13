#!/bin/bash
# ============================================================
#  IFQ testbench — compile, simulate, and open waveforms
#  Usage:
#    ./script/run_ifq_tb.sh           # compile + run
#    ./script/run_ifq_tb.sh -gui      # compile + run + open Verdi
#    ./script/run_ifq_tb.sh -clean    # remove build artifacts
# ============================================================

set -euo pipefail

# ---- paths (relative to Tomasulo3CPU/) ----
PROJ_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SRC_DIR="${PROJ_DIR}/src"
TB_DIR="${PROJ_DIR}/tb"
BUILD_DIR="${PROJ_DIR}/build"

# ---- source file list ----
SRC_FILES=(
    "${SRC_DIR}/simple_module/sync_fifo.sv"
    "${SRC_DIR}/IFQ.sv"
)
TB_FILES=(
    "${TB_DIR}/IFQ_tb.sv"
)
TOP_MODULE="IFQ_tb"
FSDB_FILE="ifq.fsdb"

# ---- parse args ----
GUI=0
CLEAN=0
for arg in "$@"; do
    case "$arg" in
        -gui)   GUI=1 ;;
        -clean) CLEAN=1 ;;
        *)      echo "Unknown arg: $arg"; exit 1 ;;
    esac
done

# ---- clean ----
if [ "$CLEAN" -eq 1 ]; then
    echo "[clean] Removing ${BUILD_DIR}"
    rm -rf "${BUILD_DIR}"
    exit 0
fi

# ---- setup build dir ----
mkdir -p "${BUILD_DIR}"
cd "${BUILD_DIR}"

# ---- compile (VCS) ----
echo "============================================"
echo "  Compiling with VCS"
echo "============================================"
vcs -full64 -sverilog -debug_access+all \
    -timescale=1ns/1ps \
    +define+FSDB_DUMP \
    +lint=all \
    "${SRC_FILES[@]}" "${TB_FILES[@]}" \
    -top "${TOP_MODULE}" \
    -o simv \
    -l compile.log \
    2>&1 | tee compile_screen.log

if [ ! -f simv ]; then
    echo "[ERROR] Compilation failed. Check build/compile.log"
    exit 1
fi

# ---- simulate ----
echo ""
echo "============================================"
echo "  Running simulation"
echo "============================================"
./simv -l sim.log +fsdbfile+${FSDB_FILE} \
    2>&1 | tee sim_screen.log

echo ""
echo "============================================"
echo "  Simulation finished — see build/sim.log"
echo "============================================"

# ---- open Verdi if requested ----
if [ "$GUI" -eq 1 ]; then
    echo "  Opening Verdi..."
    verdi -ssf "${FSDB_FILE}" -sv \
        "${SRC_FILES[@]}" "${TB_FILES[@]}" \
        -top "${TOP_MODULE}" &
fi
