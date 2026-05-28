#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from pathlib import Path
from shutil import which

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

SRC_FILES = [
    "src/riscv_funct_pkg.sv",
    "src/riscv_opcode_pkg.sv",
    "src/riscv_types_pkg.sv",
    "src/simple_module/sync_fifo.sv",
    "src/simple_module/dual_port_memory.sv",
    "src/simple_module/sync_lifo.sv",
    "src/IFQ.sv",
    "src/BPB.sv",
    "src/RAS.sv",
    "src/FRL.sv",
    "src/FRAT.sv",
    "src/ROB.sv",
    "src/RBA.sv",
    "src/RRAT.sv",
    "src/SB.sv",
    "src/RISC_V_DECODER.sv",
    "src/DISPATCH.sv",
    "src/CPU_FRONT_END.sv",
    "src/back_end/ISSUE_QUEUE/INTQ.sv",
    "src/back_end/ISSUE_QUEUE/MULQ.sv",
    "src/back_end/ISSUE_QUEUE/DIVQ.sv",
    "src/back_end/ISSUE_QUEUE/LSQ.sv",
    "src/back_end/ISSUE_QUEUE/ISSUEQ.sv",
    "src/back_end/LSB.sv",
    "src/back_end/ISSUEUNIT.sv",
    "src/back_end/PRF.sv",
    "src/back_end/EXE/ALU.sv",
    "src/back_end/EXE/DIV.sv",
    "src/back_end/EXE/MUL.sv",
    "src/back_end/EXE/EXE.sv",
    "src/back_end/CDB.sv",
    "src/back_end/CPU_BACK_END.sv",
    "src/CSR.sv",
    "src/CPU.sv",
]


def parse_tohost(meta: Path) -> int:
    text = meta.read_text(encoding="utf-8")
    m = re.search(r"TOHOST_ADDR=0x([0-9a-fA-F]+)", text)
    if not m:
        raise RuntimeError(f"Bad meta file: {meta}")
    return int(m.group(1), 16)

def ensure_questa_compiled(vsim_bin: Path) -> Path:
    build = PROJ / "build" / "questa_CPU_c_suite"
    work = build / "work"
    compiled_marker = build / ".cpu_c_suite_compiled"
    if compiled_marker.is_file() and work.is_dir():
        return build

    vlog = vsim_bin.parent / ("vlog.exe" if sys.platform == "win32" else "vlog")
    vlib = vsim_bin.parent / ("vlib.exe" if sys.platform == "win32" else "vlib")
    if not vlog.is_file() or not vlib.is_file():
        raise RuntimeError("vlib/vlog not found next to vsim")

    build.mkdir(parents=True, exist_ok=True)
    subprocess.run([str(vlib), "work"], cwd=build, check=True)
    file_list = [str((PROJ / f).resolve()) for f in SRC_FILES]
    file_list.extend([
        str((PROJ / "tb" / "dw_ip_stubs.sv").resolve()),
        str((PROJ / "tb" / "CPU_c_suite_tb.sv").resolve()),
    ])
    subprocess.run(
        [str(vlog), "-sv", "-timescale", "1ns/1ps", *file_list],
        cwd=build,
        check=True,
    )
    compiled_marker.write_text("ok\n", encoding="utf-8")
    return build


def run_one(test: str, sim: str, timeout_s: int) -> bool:
    out = BUILD / test
    imem = out / "imem.hex"
    dmem = out / "dmem.hex"
    meta = out / "meta.txt"
    if not imem.is_file() or not dmem.is_file() or not meta.is_file():
        print(f"[FAIL] {test}: missing build artifacts, run build_suite.py first")
        return False

    tohost = parse_tohost(meta)
    plusargs = (
        f"+IMEM_FILE={imem.resolve().as_posix()} "
        f"+DMEM_FILE={dmem.resolve().as_posix()} "
        f"+TOHOST_ADDR={tohost:X} "
        f"+TEST_NAME={test}"
    )

    try:
        if sim == "questa" and not which("make"):
            questa = Path(os.environ.get("QUESTA_BIN", r"D:\questasim64_2021.1\win64"))
            vsim = questa / ("vsim.exe" if sys.platform == "win32" else "vsim")
            if not vsim.is_file():
                found = which("vsim")
                if not found:
                    print("[FAIL] vsim not found; set QUESTA_BIN or PATH")
                    return False
                vsim = Path(found)
            build = ensure_questa_compiled(vsim)
            result = subprocess.run(
                [
                    str(vsim),
                    "-c",
                    "-do",
                    "run -all; quit -f",
                    "CPU_c_suite_tb",
                    f"+IMEM_FILE={imem.resolve().as_posix()}",
                    f"+DMEM_FILE={dmem.resolve().as_posix()}",
                    f"+TOHOST_ADDR={tohost:X}",
                    f"+TEST_NAME={test}",
                ],
                cwd=build,
                capture_output=True,
                text=True,
                timeout=timeout_s,
            )
        else:
            cmd = [
                "make",
                "sim-questa" if sim == "questa" else "sim",
                "USE_DW=0",
                "PROJECT=CPU_c_suite",
                f"PLUSARGS={plusargs}",
            ]
            result = subprocess.run(
                cmd,
                cwd=PROJ,
                capture_output=True,
                text=True,
                timeout=timeout_s,
            )
    except subprocess.TimeoutExpired:
        print(f"[TIMEOUT] {test}")
        return False
    except Exception as exc:
        print(f"[FAIL] {test}: {exc}")
        return False

    log = result.stdout + result.stderr
    if result.returncode == 0 and f"[PASS] c_suite PASS: {test}" in log:
        print(f"[PASS] {test}")
        return True

    print(f"[FAIL] {test} (exit {result.returncode})")
    for line in log.splitlines()[-25:]:
        print(f"  | {line}")
    return False


def main() -> int:
    parser = argparse.ArgumentParser(description="Run c_suite programs in CPU_c_suite_tb")
    parser.add_argument("tests", nargs="*", help="Optional subset of tests")
    parser.add_argument("--sim", choices=("questa", "vcs"), default="questa")
    parser.add_argument("--timeout", type=int, default=600)
    args = parser.parse_args()

    targets = args.tests if args.tests else PROGRAMS
    for t in targets:
        if t not in PROGRAMS:
            print(f"Unknown test: {t}", file=sys.stderr)
            return 1

    passed = sum(1 for t in targets if run_one(t, args.sim, args.timeout))
    total = len(targets)
    print(f"\n=== c_suite: {passed}/{total} passed ===")
    return 0 if passed == total else 1


if __name__ == "__main__":
    sys.exit(main())
