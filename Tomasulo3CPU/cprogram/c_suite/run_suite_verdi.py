#!/usr/bin/env python3
"""
Run built c_suite programs on Tomasulo3CPU simulation using VCS or QuestaSim.

Requires: cprogram/c_suite/build/<test>/imem.hex, dmem.hex, meta.txt
Simulates via: VCS (compiled once, then run directly per test) or QuestaSim.

Usage:
  python build_suite.py
  python run_suite_verdi.py
"""

from __future__ import print_function

import argparse
import concurrent.futures
import datetime
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PROJ = ROOT.parent.parent
BUILD = ROOT / "build"

PROGRAMS = [
    "memcpy",
    "memset",
    "strlen",
    "strcmp",
    "matrix_multiply",
    "linked_list",
    "recursion",
]


def read_tohost(meta_path):
    text = meta_path.read_text(encoding="utf-8")
    m = re.search(r"TOHOST_ADDR=0x([0-9a-fA-F]+)", text)
    if not m:
        raise ValueError("Bad meta file: {}".format(meta_path))
    return int(m.group(1), 16)


def _hex_path(p):
    """Resolve path to absolute string representation."""
    return p.resolve().as_posix()


def compile_simulator(sim):
    """Compile the simulation model once before running tests."""
    if sim == "vcs":
        print("=== Compiling VCS Simulation Model ===")
        cmd = ["make", "compile", "PROJECT=CPU_c_suite", "USE_DW=1"]
        try:
            res = subprocess.run(
                cmd,
                cwd=PROJ,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                universal_newlines=True
            )
            if res.returncode == 0:
                print("=== VCS Compilation Successful ===\n")
                return True
            else:
                print("=== VCS Compilation Failed ===\n", file=sys.stderr)
                print(res.stdout + res.stderr, file=sys.stderr)
                return False
        except Exception as e:
            print("Error compiling VCS simulator: {}".format(e), file=sys.stderr)
            return False

    elif sim == "questa":
        print("=== Compiling Questa Simulation Model ===")
        dummy_args = "+TEST_NAME=dummy +TOHOST_ADDR=0 +IMEM_FILE=dummy +DMEM_FILE=dummy"
        cmd = [
            "make",
            "sim-questa",
            "USE_DW=0",
            "PROJECT=CPU_c_suite",
            "PLUSARGS={}".format(dummy_args)
        ]
        try:
            subprocess.run(
                cmd,
                cwd=PROJ,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                universal_newlines=True
            )
            # Verify work directory exists
            questa_work = PROJ / "build" / "questa_CPU_c_suite" / "work"
            if questa_work.is_dir():
                print("=== Questa Compilation Successful ===\n")
                return True
            else:
                print("=== Questa Compilation Failed ===\n", file=sys.stderr)
                return False
        except Exception as e:
            print("Error compiling Questa simulator: {}".format(e), file=sys.stderr)
            return False

    return False


def run_one(test, sim, timeout_s):
    test_dir = BUILD / test
    meta = test_dir / "meta.txt"
    if not (test_dir / "imem.hex").is_file() or not (test_dir / "dmem.hex").is_file() or not meta.is_file():
        return False, "Missing build artifacts, run build_suite.py first"

    try:
        tohost = read_tohost(meta)
    except Exception as e:
        return False, "Failed to read tohost address: {}".format(e)

    if sim == "vcs":
        simv = PROJ / "build" / "CPU_c_suite" / "simv"
        if not simv.is_file():
            return False, "VCS simulator executable not found at {}.".format(simv)

        imem = _hex_path(test_dir / "imem.hex")
        dmem = _hex_path(test_dir / "dmem.hex")

        cmd = [
            str(simv),
            "-l", "sim.log",
            "+fsdbfile+CPU_c_suite.fsdb",
            "+IMEM_FILE={}".format(imem),
            "+DMEM_FILE={}".format(dmem),
            "+TOHOST_ADDR={:X}".format(tohost),
            "+TEST_NAME={}".format(test),
        ]

        try:
            result = subprocess.run(
                cmd,
                cwd=test_dir,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                universal_newlines=True,
                timeout=timeout_s,
            )
            log_path = test_dir / "sim.log"
            if log_path.is_file():
                log = log_path.read_text(encoding="utf-8", errors="ignore")
            else:
                log = result.stdout + result.stderr

            passed = (result.returncode == 0) and ("[PASS] c_suite PASS: {}".format(test) in log)
            return passed, log
        except subprocess.TimeoutExpired:
            return False, "TIMEOUT"
        except Exception as e:
            return False, "Execution failed: {}".format(e)

    elif sim == "questa":
        import os
        from shutil import which

        questa_bin = os.environ.get("QUESTA_BIN", "")
        vsim = Path(questa_bin) / ("vsim.exe" if sys.platform == "win32" else "vsim")
        if not vsim.is_file():
            found = which("vsim")
            if not found:
                return False, "vsim executable not found. Set QUESTA_BIN or add to PATH."
            vsim = Path(found)

        build = PROJ / "build" / "questa_CPU_c_suite"
        imem = _hex_path(test_dir / "imem.hex")
        dmem = _hex_path(test_dir / "dmem.hex")

        cmd = [
            str(vsim),
            "-c",
            "-do",
            "run -all; quit -f",
            "CPU_c_suite_tb",
            "+IMEM_FILE={}".format(imem),
            "+DMEM_FILE={}".format(dmem),
            "+TOHOST_ADDR={:X}".format(tohost),
            "+TEST_NAME={}".format(test),
        ]

        try:
            result = subprocess.run(
                cmd,
                cwd=build,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                universal_newlines=True,
                timeout=timeout_s,
            )
            log = result.stdout + result.stderr
            passed = (result.returncode == 0) and ("[PASS] c_suite PASS: {}".format(test) in log)
            return passed, log
        except subprocess.TimeoutExpired:
            return False, "TIMEOUT"
        except Exception as e:
            return False, "Execution failed: {}".format(e)

    return False, "Unknown simulator"


def write_results(targets, passed_tests, failed_tests, sim):
    now_str = datetime.date.today().isoformat()
    sim_name = "VCS" if sim == "vcs" else "QuestaSim"

    lines = [
        "# c_suite regression - {} ({}, {} tests)".format(now_str, sim_name, len(targets)),
        "# {}/{} PASSED".format(len(passed_tests), len(targets)),
        "",
        "## PASSED ({})".format(len(passed_tests)),
    ]

    sorted_passed = sorted(passed_tests)
    for i in range(0, len(sorted_passed), 6):
        lines.append(" ".join(sorted_passed[i:i+6]))

    lines.extend([
        "",
        "## FAILED ({})".format(len(failed_tests)),
    ])

    sorted_failed = sorted(failed_tests)
    for i in range(0, len(sorted_failed), 6):
        lines.append(" ".join(sorted_failed[i:i+6]))

    results_path = ROOT / "results_latest.txt"
    try:
        results_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
        print("\nSaved regression results to {}".format(results_path.relative_to(PROJ)))
    except Exception as e:
        print("Warning: could not write results file: {}".format(e), file=sys.stderr)


def main():
    parser = argparse.ArgumentParser(description="Run c_suite with VCS/Verdi or QuestaSim")
    parser.add_argument(
        "tests",
        nargs="*",
        help="Built test names (e.g. memcpy, recursion). Default: all c_suite tests.",
    )
    parser.add_argument(
        "--sim",
        choices=("vcs", "questa"),
        default="vcs",
        help="Simulator flow (default: vcs)",
    )
    parser.add_argument(
        "--no-compile",
        action="store_true",
        help="Skip compilation step and run simulations directly",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=60,
        help="Per-test timeout in seconds (default: 60)",
    )
    parser.add_argument(
        "--jobs", "-j",
        type=int,
        default=1,
        help="Number of parallel simulation runs (default: 1)",
    )
    args = parser.parse_args()

    targets = args.tests if args.tests else PROGRAMS
    for t in targets:
        if t not in PROGRAMS:
            print("WARNING: unknown test '{}'".format(t), file=sys.stderr)

    # Compile the simulation model first
    if not args.no_compile:
        if not compile_simulator(args.sim):
            print("ERROR: Compilation failed. Aborting regression run.", file=sys.stderr)
            return 1

    # Adjust jobs based on simulator choice
    jobs = args.jobs
    if args.sim == "questa" and jobs > 1:
        print("WARNING: Parallel execution is not supported for QuestaSim. Falling back to sequential execution.", file=sys.stderr)
        jobs = 1

    passed_list = []
    failed_list = []
    failed_details = []

    print("Running {} tests using {} (jobs={})...".format(len(targets), args.sim.upper(), jobs))

    if jobs > 1:
        with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as executor:
            future_to_test = {
                executor.submit(run_one, t, args.sim, args.timeout): t for t in targets
            }
            for future in concurrent.futures.as_completed(future_to_test):
                t = future_to_test[future]
                try:
                    passed, log = future.result()
                    if passed:
                        print("[PASS] {}".format(t))
                        passed_list.append(t)
                    else:
                        print("[FAIL] {}".format(t))
                        failed_list.append(t)
                        failed_details.append((t, log))
                except Exception as exc:
                    print("[ERROR] {} raised exception: {}".format(t, exc))
                    failed_list.append(t)
                    failed_details.append((t, "Exception: {}".format(exc)))
    else:
        for t in targets:
            passed, log = run_one(t, args.sim, args.timeout)
            if passed:
                print("[PASS] {}".format(t))
                passed_list.append(t)
            else:
                print("[FAIL] {}".format(t))
                failed_list.append(t)
                failed_details.append((t, log))

    # Print summary
    print("\n==========================================")
    print("Regression completed: {}/{} passed.".format(len(passed_list), len(targets)))
    print("==========================================")

    if failed_details:
        print("\n=== Failure Details ===")
        for name, log in failed_details:
            print("\n--- {} Failure Log (Last 30 lines) ---".format(name))
            log_lines = log.splitlines()
            for line in log_lines[-30:]:
                print("  | {}".format(line))

    # Write out results log file
    write_results(targets, passed_list, failed_list, args.sim)

    return 0 if len(passed_list) == len(targets) else 1


if __name__ == "__main__":
    sys.exit(main())
