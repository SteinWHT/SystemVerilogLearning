#!/bin/bash
# ============================================================================
# build_spike_dpi.sh — build the Spike DPI-C lockstep co-sim for the CentOS-7
# VCS runtime, then (optionally) compile/run the constrained-random UVM test.
#
# WHY THIS EXISTS
# ---------------
# VCS runs inside the CentOS-7 Synopsys docker (glibc 2.17, stock g++ 4.8.5).
# The Spike libraries that were built on the Ubuntu host (build_ubuntu/) link
# against glibc 2.38 / GLIBCXX 3.4.32 and therefore CANNOT load in that runtime.
# So Spike must be rebuilt *inside* the container with a toolchain that targets
# glibc 2.17 and supports C++17/20. The only such native x86_64 compiler on this
# machine is the Xilinx-bundled gcc-9.3.0. This script:
#
#   1. Recreates a container-native build of Spike's static archives in
#      build_centos/ (reusing build_ubuntu's already-configured Makefile +
#      generated sources, so no ./configure and no Boost *libraries* are needed
#      — only Boost *headers*, to compile sim/socketif/interactive.cc).
#   2. Builds libspike_cosim.so via the project Makefile, statically linking
#      libstdc++/libgcc so the .so is self-contained (NEEDED = libm/libc/ld only,
#      max GLIBC 2.14) and loads cleanly under the CentOS-7 VCS.
#
# RUN THIS *INSIDE* THE CONTAINER (script/run_synopsys.sh), e.g.:
#   bash script/build_spike_dpi.sh             # build archives (if missing) + shim
#   bash script/build_spike_dpi.sh --full      # force full Spike archive rebuild
#   bash script/build_spike_dpi.sh --run        # also compile + run the UVM DPI test
#
# PREREQUISITE for a FULL archive rebuild: Boost *headers* visible at /opt/boost.
# run_synopsys.sh does not mount them by default; add this to its `docker run`:
#       -v /usr/include/boost:/opt/boost/boost:ro
# (The frequent case — rebuilding only the shim — needs NO Boost.)
# ============================================================================
set -euo pipefail

GCC9="${GCC9:-/data/tools/Xilinx/Vitis_HLS/2024.1/tps/lnx64/gcc-9.3.0}"
BOOST_INC="${BOOST_INC:-/opt/boost}"
export LD_LIBRARY_PATH="$GCC9/lib64:${LD_LIBRARY_PATH:-}"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJ_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"           # Tomasulo3CPU
SP="$PROJ_DIR/tools/riscv-isa-sim"
SRC_BUILD="$SP/build_ubuntu"                        # host-configured reference build
CENTOS_BUILD="$SP/build_centos"                     # container-native archives
LIBS="libriscv.a libdisasm.a libsoftfloat.a libfdt.a"   # libfesvr handled separately

FULL=0; DO_RUN=0
for a in "$@"; do
  case "$a" in
    --full) FULL=1 ;;
    --run)  DO_RUN=1 ;;
    *) echo "unknown arg: $a"; exit 2 ;;
  esac
done

[ -x "$GCC9/bin/g++-9.3.0" ] || { echo "ERROR: gcc-9.3.0 not found at $GCC9"; exit 1; }

# --- 1. Container-native Spike static archives --------------------------------
if [ "$FULL" = 1 ] || [ ! -f "$CENTOS_BUILD/libriscv.a" ]; then
  echo "==> Rebuilding Spike static archives in build_centos/ (gcc-9.3.0)"
  [ -d "$SRC_BUILD" ] || { echo "ERROR: reference build_ubuntu/ missing"; exit 1; }
  [ -d "$BOOST_INC/boost" ] || {
    echo "ERROR: Boost headers not at $BOOST_INC/boost — a full archive rebuild"
    echo "       needs them. Re-launch the container mounting:"
    echo "         -v /usr/include/boost:/opt/boost/boost:ro"
    exit 1; }

  rm -rf "$CENTOS_BUILD"; mkdir -p "$CENTOS_BUILD"
  # Reuse the configured Makefile + generated sources/headers (src_dir := .. is
  # relative, so a sibling build dir Just Works). Skip .o/.a/.so/.d artifacts.
  cp "$SRC_BUILD/Makefile" "$SRC_BUILD/config.status" "$CENTOS_BUILD/"
  cp "$SRC_BUILD"/*.cc "$SRC_BUILD"/*.h "$SRC_BUILD"/*.mk "$CENTOS_BUILD/"
  find "$CENTOS_BUILD" -exec touch {} +    # normalize mtimes so autoconf-regen rules stay dormant

  ( cd "$CENTOS_BUILD"
    make -j"$(nproc)" -k \
      CC="$GCC9/bin/gcc-9.3.0" \
      CXX="$GCC9/bin/g++-9.3.0 -std=c++2a -fconcepts -I$BOOST_INC" \
      $LIBS || true                      # -k: keep going past the one known failure

    # fesvr: syscall.cc uses struct statx (absent on glibc 2.17). The cosim shim
    # never proxies syscalls, so archive every fesvr object EXCEPT syscall.o.
    objs=""
    for o in $(ar t "$SRC_BUILD/libfesvr.a"); do
      [ "$o" = "syscall.o" ] && continue
      [ -f "$o" ] && objs="$objs $o"
    done
    ar rcs libfesvr.a $objs
  )
  for l in $LIBS libfesvr.a; do
    [ -f "$CENTOS_BUILD/$l" ] || { echo "ERROR: $l not built"; exit 1; }
  done
  echo "==> Spike archives ready in build_centos/"
else
  echo "==> Reusing existing build_centos/ archives (use --full to force rebuild)"
fi

# --- 2. Self-contained DPI shim via the project Makefile ----------------------
echo "==> Building libspike_cosim.so (static libstdc++/libgcc)"
cd "$PROJ_DIR"
SHIM_CXXFLAGS="-fconcepts -I$CENTOS_BUILD"
[ -d "$BOOST_INC/boost" ] && SHIM_CXXFLAGS="$SHIM_CXXFLAGS -I$BOOST_INC"
make spike-cosim-lib ENABLE_SPIKE_DPI=1 \
  CXX="$GCC9/bin/g++-9.3.0" SPIKE_CXXSTD=c++2a \
  SPIKE_CXXFLAGS="$SHIM_CXXFLAGS" \
  SPIKE_LIB_DIR="$CENTOS_BUILD" \
  SPIKE_EXTRA_LDFLAGS="-static-libstdc++ -static-libgcc"

SHIM="$PROJ_DIR/uvm/tools/spike_cosim/libspike_cosim.so"
echo "==> Built $SHIM"
echo "    NEEDED:"; readelf -d "$SHIM" | grep NEEDED | sed 's/^/      /'
echo "    max GLIBC: $(objdump -T "$SHIM" | grep -oE 'GLIBC_[0-9.]+' | sort -V | tail -1) (container has 2.17)"

# --- 3. Optional: compile + run the constrained-random UVM DPI test -----------
if [ "$DO_RUN" = 1 ]; then
  echo "==> Compiling + running cpu_constrained_random_test with Spike DPI"
  MAKEVARS=(ENABLE_SPIKE_DPI=1 UVM_TEST=cpu_constrained_random_test
            CXX="$GCC9/bin/g++-9.3.0" SPIKE_CXXSTD=c++2a
            SPIKE_CXXFLAGS="$SHIM_CXXFLAGS"
            SPIKE_LIB_DIR="$CENTOS_BUILD"
            SPIKE_EXTRA_LDFLAGS="-static-libstdc++ -static-libgcc")
  make uvm-compile "${MAKEVARS[@]}"
  make uvm "${MAKEVARS[@]}" \
    PLUSARGS="+CR_NUM_INSTR=300 +CR_RAW_PCT=60 +CR_WAW_PCT=30 +CR_LOAD_USE_PCT=40 +CR_SEED=1"
fi
echo "==> Done."
