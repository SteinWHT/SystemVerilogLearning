#!/usr/bin/env python3
"""
Run built riscv-tests on Tomasulo3CPU simulation.

Requires: arch_test/build/<suite>-<test>/imem.hex, dmem.hex, meta.txt
Simulates via: make sim-questa USE_DW=0 PROJECT=CPU_riscv_tests (or VCS)

Usage:
  python build_tests.py add
  python run_tests.py add
  python run_tests.py          # all built tests
"""

from __future__ import annotations

import argparse
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PROJ = ROOT.parent
BUILD = ROOT / "build"


def list_built_tests() -> list[str]:
    if not BUILD.is_dir():
        return []
    out: list[str] = []
    for d in sorted(BUILD.iterdir()):
        if d.is_dir() and (d / "imem.hex").is_file() and (d / "meta.txt").is_file():
            out.append(d.name)
    return out


def read_tohost(meta_path: Path) -> int:
    text = meta_path.read_text(encoding="utf-8")
    m = re.search(r"TOHOST_ADDR=0x([0-9a-fA-F]+)", text)
    if not m:
        raise ValueError(f"Bad meta file: {meta_path}")
    return int(m.group(1), 16)


def _hex_path(p: Path) -> str:
    """Forward slashes for Questa $readmemh on Windows."""
    return p.resolve().as_posix()


def run_questa_direct(test_dir: Path, tohost: int, timeout_s: int) -> subprocess.CompletedProcess:
    """Run Questa without make (Windows-friendly)."""
    import os
    from shutil import which

    questa = Path(os.environ.get("QUESTA_BIN", r"D:\questasim64_2021.1\win64"))
    vsim = questa / ("vsim.exe" if sys.platform == "win32" else "vsim")
    if not vsim.is_file():
        found = which("vsim")
        if not found:
            raise RuntimeError("vsim not found; set QUESTA_BIN or add Questa to PATH")
        vsim = Path(found)

    build = PROJ / "build" / "questa_CPU_riscv_tests"
    imem = _hex_path(test_dir / "imem.hex")
    dmem = _hex_path(test_dir / "dmem.hex")
    return subprocess.run(
        [
            str(vsim),
            "-c",
            "-do",
            "run -all; quit -f",
            "CPU_riscv_tests_tb",
            f"+IMEM_FILE={imem}",
            f"+DMEM_FILE={dmem}",
            f"+TOHOST_ADDR={tohost:X}",
            f"+TEST_NAME={test_dir.name}",
        ],
        cwd=build,
        capture_output=True,
        text=True,
        timeout=timeout_s,
    )


def run_one(test_dir: Path, sim: str, timeout_s: int) -> bool:
    meta = test_dir / "meta.txt"
    tohost = read_tohost(meta)
    try:
        if sim == "questa":
            from shutil import which

            if which("make"):
                plusargs = (
                    f"+IMEM_FILE={_hex_path(test_dir / 'imem.hex')} "
                    f"+DMEM_FILE={_hex_path(test_dir / 'dmem.hex')} "
                    f"+TOHOST_ADDR={tohost:X} "
                    f"+TEST_NAME={test_dir.name}"
                )
                result = subprocess.run(
                    [
                        "make",
                        "sim-questa",
                        "USE_DW=0",
                        "PROJECT=CPU_riscv_tests",
                        f"PLUSARGS={plusargs}",
                    ],
                    cwd=PROJ,
                    capture_output=True,
                    text=True,
                    timeout=timeout_s,
                )
            else:
                result = run_questa_direct(test_dir, tohost, timeout_s)
        else:
            plusargs = (
                f"+IMEM_FILE={_hex_path(test_dir / 'imem.hex')} "
                f"+DMEM_FILE={_hex_path(test_dir / 'dmem.hex')} "
                f"+TOHOST_ADDR={tohost:X} "
                f"+TEST_NAME={test_dir.name}"
            )
            result = subprocess.run(
                [
                    "make",
                    "sim",
                    "USE_DW=0",
                    "PROJECT=CPU_riscv_tests",
                    f"PLUSARGS={plusargs}",
                ],
                cwd=PROJ,
                capture_output=True,
                text=True,
                timeout=timeout_s,
            )
    except subprocess.TimeoutExpired:
        print(f"[TIMEOUT] {test_dir.name}")
        return False
    log = result.stdout + result.stderr
    if result.returncode == 0 and "[PASS]" in log and "riscv_test PASS" in log:
        print(f"[PASS] {test_dir.name}")
        return True
    print(f"[FAIL] {test_dir.name} (exit {result.returncode})")
    for line in log.splitlines()[-30:]:
        print(f"  | {line}")
    return False


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "tests",
        nargs="*",
        help="Built test dirs (e.g. rv64ui-add) or short names (add)",
    )
    parser.add_argument(
        "--sim",
        choices=("questa", "vcs"),
        default="questa",
        help="Simulator flow (default: questa)",
    )
    parser.add_argument(
        "--timeout",
        type=int,
        default=600,
        help="Per-test timeout in seconds",
    )
    args = parser.parse_args()

    if args.tests:
        dirs: list[Path] = []
        for t in args.tests:
            if (BUILD / t).is_dir():
                dirs.append(BUILD / t)
            elif (BUILD / f"rv64ui-{t}").is_dir():
                dirs.append(BUILD / f"rv64ui-{t}")
            elif (BUILD / f"rv64um-{t}").is_dir():
                dirs.append(BUILD / f"rv64um-{t}")
            else:
                print(f"WARNING: no build dir for '{t}'", file=sys.stderr)
    else:
        dirs = [BUILD / n for n in list_built_tests()]

    if not dirs:
        print("No tests to run. Build first: python arch_test/build_tests.py add", file=sys.stderr)
        return 1

    passed = sum(run_one(d, args.sim, args.timeout) for d in dirs)
    total = len(dirs)
    print(f"\n=== {passed}/{total} riscv-tests passed ===")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
