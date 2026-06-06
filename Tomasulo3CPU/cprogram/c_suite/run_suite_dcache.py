#!/usr/bin/env python3
"""
Run the bare-metal C suite on Tomasulo3CPU with the L1 D-cache.

The default system uses the full path:
  CPU -> L1 D-cache -> AXI4 bridge -> AXI fabric -> AXI SRAM

Use --system dcache for the original CPU + L1 D-cache + behavioral backing
memory testbench. Both systems reuse the build artifacts from build_suite.py
(build/<test>/imem.hex, dmem.hex, meta.txt).

Usage:
  python build_suite.py            # build the C programs first
  python run_suite_dcache.py       # run all tests through the AXI4 system
  python run_suite_dcache.py --system dcache
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

PROGRAMS = [
    "memcpy", "memset", "strlen", "strcmp", "matrix_multiply",
    "linked_list", "recursion", "csr_trap", "wide_data", "deep_recursion",
    "matrix_cache_stress", "fibonacci_stress",
]

SYSTEMS = {
    "axi": {
        "project": "CPU_dcache_axi",
        "description": "CPU + L1 D-cache + AXI4",
        "pass_re": r"^\[PASS\] {test} \(",
        "log_name": "sim_dcache_axi.log",
    },
    "dcache": {
        "project": "CPU_dcache_c",
        "description": "CPU + L1 D-cache",
        "pass_re": r"^\[PASS\] c_suite PASS: {test} ",
        "log_name": "sim_dcache.log",
    },
}


def read_tohost(meta_path):
    m = re.search(r"TOHOST_ADDR=0x([0-9a-fA-F]+)", meta_path.read_text(encoding="utf-8"))
    if not m:
        raise ValueError("Bad meta file: {}".format(meta_path))
    return int(m.group(1), 16)


def compile_model(system):
    cfg = SYSTEMS[system]
    project = cfg["project"]
    print("=== Compiling VCS model ({}) ===".format(project))
    cmd = ["make", "compile", "PROJECT={}".format(project), "USE_DW=1"]
    res = subprocess.run(cmd, cwd=PROJ)
    return res.returncode == 0


def run_one(test, system, timeout_s, max_cycles):
    cfg = SYSTEMS[system]
    project = cfg["project"]
    test_dir = BUILD / test
    imem = test_dir / "imem.hex"
    dmem = test_dir / "dmem.hex"
    meta = test_dir / "meta.txt"
    if not imem.is_file() or not dmem.is_file() or not meta.is_file():
        return False, "Missing build artifacts; run build_suite.py first"
    try:
        tohost = read_tohost(meta)
    except (OSError, ValueError) as exc:
        return False, "Failed to read tohost address: {}".format(exc)

    simv = PROJ / "build" / project / "simv"
    if not simv.is_file():
        return False, "simv not found at {}".format(simv)

    cmd = [
        str(simv), "-l", cfg["log_name"],
        "+IMEM_FILE={}".format(imem.resolve()),
        "+DMEM_FILE={}".format(dmem.resolve()),
        "+TOHOST_ADDR={:X}".format(tohost),
        "+TEST_NAME={}".format(test),
    ]
    if system == "axi":
        cmd.append("+MAX_CYCLES={}".format(max_cycles))

    try:
        result = subprocess.run(cmd, cwd=test_dir, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT, universal_newlines=True,
                                timeout=timeout_s)
        log = result.stdout
        pass_re = cfg["pass_re"].format(test=re.escape(test))
        passed = result.returncode == 0 and re.search(
            pass_re, log, flags=re.MULTILINE
        ) is not None
        return passed, log
    except subprocess.TimeoutExpired:
        return False, "TIMEOUT"
    except OSError as exc:
        return False, "Execution failed: {}".format(exc)


def main():
    ap = argparse.ArgumentParser(
        description="Run C suite on the D-cache systems (default: AXI4)"
    )
    ap.add_argument("tests", nargs="*", help="subset (default: all)")
    ap.add_argument(
        "--system",
        choices=tuple(SYSTEMS),
        default="axi",
        help="memory system: axi (default) or original dcache backing memory",
    )
    ap.add_argument("--no-compile", action="store_true")
    ap.add_argument(
        "--timeout",
        type=int,
        default=600,
        help="wall-clock timeout per test in seconds (default: 600)",
    )
    ap.add_argument(
        "--max-cycles",
        type=int,
        default=5_000_000,
        help="AXI testbench cycle limit (default: 5000000)",
    )
    args = ap.parse_args()

    targets = args.tests if args.tests else PROGRAMS
    unknown = [test for test in targets if test not in PROGRAMS]
    if unknown:
        print("ERROR: unknown test(s): {}".format(", ".join(unknown)),
              file=sys.stderr)
        return 1
    if args.timeout <= 0:
        ap.error("--timeout must be greater than zero")
    if args.max_cycles <= 0:
        ap.error("--max-cycles must be greater than zero")

    cfg = SYSTEMS[args.system]
    if not args.no_compile and not compile_model(args.system):
        print("ERROR: compilation failed", file=sys.stderr)
        return 1

    print("=== Running {} ({}) ===".format(
        cfg["description"], cfg["project"]
    ))
    passed, failed = [], []
    for t in targets:
        ok, log = run_one(t, args.system, args.timeout, args.max_cycles)
        print("[{}] {}".format("PASS" if ok else "FAIL", t))
        (passed if ok else failed).append(t)
        if not ok:
            for line in log.splitlines()[-15:]:
                print("   | {}".format(line))

    print("\n==========================================")
    print("{}: {}/{} passed".format(
        cfg["description"], len(passed), len(targets)
    ))
    print("==========================================")
    return 0 if not failed else 1


if __name__ == "__main__":
    sys.exit(main())
