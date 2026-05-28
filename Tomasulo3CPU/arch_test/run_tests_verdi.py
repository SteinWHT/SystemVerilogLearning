#!/usr/bin/env python3
"""
Run built riscv-tests on Tomasulo3CPU simulation.

Requires: arch_test/build/<suite>-<test>/imem.hex, dmem.hex, meta.txt
Simulates via: VCS (compiled once, then run directly per test) or QuestaSim.

Usage:
  python build_tests.py add
  python run_tests_verdi.py add
  python run_tests_verdi.py          # all built tests
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
PROJ = ROOT.parent
BUILD = ROOT / "build"


def list_built_tests():
    if not BUILD.is_dir():
        return []
    out = []
    for d in sorted(BUILD.iterdir()):
        if d.is_dir() and (d / "imem.hex").is_file() and (d / "meta.txt").is_file():
            out.append(d.name)
    return out


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
        # Run make compile
        cmd = ["make", "compile", "PROJECT=CPU_riscv_tests"]
        try:
            res = subprocess.run(cmd, cwd=PROJ)
            if res.returncode == 0:
                print("=== VCS Compilation Successful ===\n")
                return True
            else:
                print("=== VCS Compilation Failed ===\n", file=sys.stderr)
                return False
        except Exception as e:
            print("Error compiling VCS simulator: {}".format(e), file=sys.stderr)
            return False
            
    elif sim == "questa":
        print("=== Compiling Questa Simulation Model ===")
        # Run vlib and vlog by invoking make once with dummy arguments
        # so we don't have to duplicate the file lists in Python.
        # This compiles the work library.
        dummy_args = "+TEST_NAME=dummy +TOHOST_ADDR=0 +IMEM_FILE=dummy +DMEM_FILE=dummy"
        cmd = [
            "make",
            "sim-questa",
            "USE_DW=0",
            "PROJECT=CPU_riscv_tests",
            "PLUSARGS={}".format(dummy_args)
        ]
        try:
            # We discard output since this run will fail on dummy files, but compilation will succeed.
            subprocess.run(cmd, cwd=PROJ, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            # Verify work directory exists
            questa_work = PROJ / "build" / "questa_CPU_riscv_tests" / "work"
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


def run_one(test_dir, sim, timeout_s):
    meta = test_dir / "meta.txt"
    try:
        tohost = read_tohost(meta)
    except Exception as e:
        return False, "Failed to read tohost address: {}".format(e)
        
    if sim == "vcs":
        simv = PROJ / "build" / "CPU_riscv_tests" / "simv"
        if not simv.is_file():
            return False, "VCS simulator executable not found at {}.".format(simv)
            
        imem = _hex_path(test_dir / "imem.hex")
        dmem = _hex_path(test_dir / "dmem.hex")
        
        cmd = [
            str(simv),
            "-l", "sim.log",
            "+fsdbfile+CPU_riscv_tests.fsdb",
            "+IMEM_FILE={}".format(imem),
            "+DMEM_FILE={}".format(dmem),
            "+TOHOST_ADDR={:X}".format(tohost),
            "+TEST_NAME={}".format(test_dir.name),
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
            # Read log file if created
            log_path = test_dir / "sim.log"
            if log_path.is_file():
                log = log_path.read_text(encoding="utf-8", errors="ignore")
            else:
                log = result.stdout + result.stderr
                
            passed = (result.returncode == 0) and ("[PASS]" in log and "riscv_test PASS" in log)
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

        build = PROJ / "build" / "questa_CPU_riscv_tests"
        imem = _hex_path(test_dir / "imem.hex")
        dmem = _hex_path(test_dir / "dmem.hex")
        
        cmd = [
            str(vsim),
            "-c",
            "-do",
            "run -all; quit -f",
            "CPU_riscv_tests_tb",
            "+IMEM_FILE={}".format(imem),
            "+DMEM_FILE={}".format(dmem),
            "+TOHOST_ADDR={:X}".format(tohost),
            "+TEST_NAME={}".format(test_dir.name),
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
            passed = (result.returncode == 0) and ("[PASS]" in log and "riscv_test PASS" in log)
            return passed, log
        except subprocess.TimeoutExpired:
            return False, "TIMEOUT"
        except Exception as e:
            return False, "Execution failed: {}".format(e)
            
    return False, "Unknown simulator"


def write_results(dirs, passed_tests, failed_tests, sim):
    now_str = datetime.date.today().isoformat()
    sim_name = "VCS" if sim == "vcs" else "QuestaSim"
    
    lines = [
        "# riscv-tests regression - {} ({}, {} tests in manifest)".format(now_str, sim_name, len(dirs)),
        "# {}/{} PASSED".format(len(passed_tests), len(dirs)),
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
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "tests",
        nargs="*",
        help="Built test dirs (e.g. rv64ui-add) or short names (add)",
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

    if args.tests:
        dirs = []
        for t in args.tests:
            if (BUILD / t).is_dir():
                dirs.append(BUILD / t)
            elif (BUILD / ("rv64ui-" + t)).is_dir():
                dirs.append(BUILD / ("rv64ui-" + t))
            elif (BUILD / ("rv64um-" + t)).is_dir():
                dirs.append(BUILD / ("rv64um-" + t))
            else:
                print("WARNING: no build dir for '{}'".format(t), file=sys.stderr)
    else:
        dirs = [BUILD / n for n in list_built_tests()]

    if not dirs:
        print("No tests to run. Build first: python arch_test/build_tests.py add", file=sys.stderr)
        return 1

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

    print("Running {} tests using {} (jobs={})...".format(len(dirs), args.sim.upper(), jobs))

    if jobs > 1:
        with concurrent.futures.ThreadPoolExecutor(max_workers=jobs) as executor:
            future_to_dir = {
                executor.submit(run_one, d, args.sim, args.timeout): d for d in dirs
            }
            for future in concurrent.futures.as_completed(future_to_dir):
                d = future_to_dir[future]
                name = d.name
                try:
                    passed, log = future.result()
                    if passed:
                        print("[PASS] {}".format(name))
                        passed_list.append(name)
                    else:
                        print("[FAIL] {}".format(name))
                        failed_list.append(name)
                        failed_details.append((name, log))
                except Exception as exc:
                    print("[ERROR] {} raised exception: {}".format(name, exc))
                    failed_list.append(name)
                    failed_details.append((name, "Exception: {}".format(exc)))
    else:
        for d in dirs:
            name = d.name
            passed, log = run_one(d, args.sim, args.timeout)
            if passed:
                print("[PASS] {}".format(name))
                passed_list.append(name)
            else:
                print("[FAIL] {}".format(name))
                failed_list.append(name)
                failed_details.append((name, log))

    # Print summary
    print("\n==========================================")
    print("Regression completed: {}/{} passed.".format(len(passed_list), len(dirs)))
    print("==========================================")

    if failed_details:
        print("\n=== Failure Details ===")
        for name, log in failed_details:
            print("\n--- {} Failure Log (Last 30 lines) ---".format(name))
            log_lines = log.splitlines()
            for line in log_lines[-30:]:
                print("  | {}".format(line))

    # Write out results log file
    write_results(dirs, passed_list, failed_list, args.sim)

    return 0 if len(passed_list) == len(dirs) else 1


if __name__ == "__main__":
    sys.exit(main())
