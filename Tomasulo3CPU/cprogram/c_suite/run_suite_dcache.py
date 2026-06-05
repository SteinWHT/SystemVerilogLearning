#!/usr/bin/env python3
"""
Run the bare-metal C suite on Tomasulo3CPU *with the L1 D-cache* (PROJECT=
CPU_dcache_c, tb/CPU_dcache_c_tb.sv).  Reuses the same build artifacts as
run_suite_verdi.py (build/<test>/imem.hex, dmem.hex, meta.txt).

Usage:
  python build_suite.py            # build the C programs first
  python run_suite_dcache.py       # run all tests through CPU + L1 D-cache
  python run_suite_dcache.py strlen memcpy
"""

from __future__ import print_function

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PROJ = ROOT.parent.parent
BUILD = ROOT / "build"
PROJECT = "CPU_dcache_c"

PROGRAMS = [
    "memcpy", "memset", "strlen", "strcmp", "matrix_multiply",
    "linked_list", "recursion", "csr_trap", "wide_data", "deep_recursion",
]


def read_tohost(meta_path):
    m = re.search(r"TOHOST_ADDR=0x([0-9a-fA-F]+)", meta_path.read_text(encoding="utf-8"))
    if not m:
        raise ValueError("Bad meta file: {}".format(meta_path))
    return int(m.group(1), 16)


def compile_model():
    print("=== Compiling VCS model ({}) ===".format(PROJECT))
    cmd = ["make", "compile", "PROJECT={}".format(PROJECT), "USE_DW=1"]
    res = subprocess.run(cmd, cwd=PROJ)
    return res.returncode == 0


def run_one(test, timeout_s):
    test_dir = BUILD / test
    meta = test_dir / "meta.txt"
    if not (test_dir / "imem.hex").is_file() or not meta.is_file():
        return False, "Missing build artifacts; run build_suite.py first"
    tohost = read_tohost(meta)
    simv = PROJ / "build" / PROJECT / "simv"
    if not simv.is_file():
        return False, "simv not found at {}".format(simv)

    cmd = [
        str(simv), "-l", "sim_dcache.log",
        "+IMEM_FILE={}".format((test_dir / "imem.hex").resolve()),
        "+DMEM_FILE={}".format((test_dir / "dmem.hex").resolve()),
        "+TOHOST_ADDR={:X}".format(tohost),
        "+TEST_NAME={}".format(test),
    ]
    try:
        result = subprocess.run(cmd, cwd=test_dir, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, universal_newlines=True,
                                timeout=timeout_s)
        log = result.stdout
        passed = "[PASS] c_suite PASS: {}".format(test) in log
        return passed, log
    except subprocess.TimeoutExpired:
        return False, "TIMEOUT"


def main():
    ap = argparse.ArgumentParser(description="Run C suite on CPU + L1 D-cache")
    ap.add_argument("tests", nargs="*", help="subset (default: all)")
    ap.add_argument("--no-compile", action="store_true")
    ap.add_argument("--timeout", type=int, default=120)
    args = ap.parse_args()

    targets = args.tests if args.tests else PROGRAMS
    if not args.no_compile and not compile_model():
        print("ERROR: compilation failed", file=sys.stderr)
        return 1

    passed, failed = [], []
    for t in targets:
        ok, log = run_one(t, args.timeout)
        print("[{}] {}".format("PASS" if ok else "FAIL", t))
        (passed if ok else failed).append(t)
        if not ok:
            for line in log.splitlines()[-15:]:
                print("   | {}".format(line))

    print("\n==========================================")
    print("CPU + L1 D-cache: {}/{} passed".format(len(passed), len(targets)))
    print("==========================================")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
