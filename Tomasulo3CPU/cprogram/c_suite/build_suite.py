#!/usr/bin/env python3
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
ARCH_TEST = ROOT.parent.parent / "arch_test"
sys.path.insert(0, str(ARCH_TEST))

from elf_to_hex import convert_elf  # type: ignore
from riscv_toolchain import resolve_bin_dir, resolve_prefix, tool_path  # type: ignore

PROGRAMS = [
    "memcpy",
    "memset",
    "strlen",
    "strcmp",
    "matrix_multiply",
    "linked_list",
    "recursion",
]


def run_cmd(cmd: list[str], cwd: Path) -> int:
    print(f"[RUN] ({cwd.name}) {' '.join(cmd)}")
    return subprocess.run(cmd, cwd=cwd).returncode


def build_one(test: str, clean: bool, bin_dir: Path | None) -> int:
    toolchain_bin = resolve_bin_dir(bin_dir)
    prefix = resolve_prefix(toolchain_bin)
    cc = tool_path(toolchain_bin, prefix, "gcc")
    objdump = tool_path(toolchain_bin, prefix, "objdump")
    size = tool_path(toolchain_bin, prefix, "size")

    td = ROOT / test
    out = ROOT / "build" / test
    elf = out / f"{test}.elf"
    dump = out / f"{test}.dump"
    link = ROOT / "common" / "link.ld"
    start = ROOT / "common" / "start.S"
    runtime = ROOT / "common" / "runtime.c"
    main = td / "main.c"

    out.mkdir(parents=True, exist_ok=True)
    if clean and out.is_dir():
        for f in out.iterdir():
            if f.is_file():
                f.unlink()

    cflags = [
        "-march=rv64im",
        "-mabi=lp64",
        "-nostdlib",
        "-nostartfiles",
        "-ffreestanding",
        "-fno-builtin",
        "-O1",
        "-Wall",
        "-Wextra",
        "-Wno-unused-parameter",
        "-T",
        str(link),
        "-o",
        str(elf),
        str(start),
        str(runtime),
        str(main),
    ]
    if run_cmd([cc, *cflags], td) != 0:
        return 1
    if run_cmd([objdump, "-d", "-M", "no-aliases", str(elf)], td) != 0:
        return 1
    dump.write_text(
        subprocess.check_output([objdump, "-d", "-M", "no-aliases", str(elf)], text=True),
        encoding="utf-8",
    )
    convert_elf(elf, out, toolchain_bin)
    run_cmd([size, str(elf)], td)
    return 0


def main() -> int:
    parser = argparse.ArgumentParser(description="Build all c_suite programs")
    parser.add_argument("tests", nargs="*", help="Optional subset of tests")
    parser.add_argument("--clean", action="store_true", help="Run make clean first")
    parser.add_argument("--bin-dir", type=Path, default=None, help="RISC-V toolchain bin directory")
    args = parser.parse_args()

    targets = args.tests if args.tests else PROGRAMS
    for t in targets:
        if t not in PROGRAMS:
            print(f"Unknown test: {t}", file=sys.stderr)
            return 1

    for test in targets:
        td = ROOT / test
        if not td.is_dir():
            print(f"Missing directory: {td}", file=sys.stderr)
            return 1
        if build_one(test, args.clean, args.bin_dir) != 0:
            return 1

    print(f"\nBuilt {len(targets)} test(s) successfully.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
