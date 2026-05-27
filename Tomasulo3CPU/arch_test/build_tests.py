#!/usr/bin/env python3
"""
Build riscv-tests (riscv-software-src/riscv-tests) for Tomasulo3CPU.

Usage:
  python build_tests.py              # build all tests in manifests
  python build_tests.py add beq mul  # build named tests only
"""

from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
PROJ = ROOT.parent
RISCV_TESTS = PROJ / "third_party" / "riscv-tests"
ISA = RISCV_TESTS / "isa"
ENV_INC = ROOT / "env"
ENV_ENCODING = RISCV_TESTS / "env"
MACROS = ISA / "macros" / "scalar"
LINKER = ROOT / "link_tomasulo.ld"
BUILD = ROOT / "build"

from riscv_toolchain import resolve_bin_dir, resolve_prefix, tool_path


def read_manifest(name: str) -> list[str]:
    path = ROOT / name
    tests: list[str] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        tests.append(line)
    return tests


def compile_test(bin_dir: Path, prefix: str, suite: str, test: str) -> Path:
    src = ISA / suite / f"{test}.S"
    if not src.is_file():
        raise FileNotFoundError(src)
    out_dir = BUILD / f"{suite}-{test}"
    out_dir.mkdir(parents=True, exist_ok=True)
    elf = out_dir / f"{test}.elf"
    gcc = tool_path(bin_dir, prefix, "gcc")
    cmd = [
        gcc,
        "-march=rv64im_zicsr",
        "-mabi=lp64",
        "-static",
        "-mcmodel=medany",
        "-fvisibility=hidden",
        "-nostdlib",
        "-nostartfiles",
        f"-I{ENV_INC}",
        f"-I{ENV_ENCODING}",
        f"-I{MACROS}",
        f"-T{LINKER}",
        str(src),
        "-o",
        str(elf),
    ]
    subprocess.run(cmd, check=True)
    return elf


def hexify(elf: Path, out_dir: Path, bin_dir: Path) -> None:
    script = ROOT / "elf_to_hex.py"
    subprocess.run(
        [
            sys.executable,
            str(script),
            str(elf),
            "-o",
            str(out_dir),
            "--bin-dir",
            str(bin_dir),
        ],
        check=True,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "tests",
        nargs="*",
        help="Test base names (e.g. add beq). Default: all manifests.",
    )
    parser.add_argument(
        "--bin-dir",
        type=Path,
        default=None,
        help="Toolchain bin directory (e.g. D:/riscv-toolchain/.../bin)",
    )
    args = parser.parse_args()

    if not (RISCV_TESTS / "env" / "encoding.h").is_file():
        print(
            "ERROR: riscv-tests env not found. Run:\n"
            f"  cd {RISCV_TESTS} && git submodule update --init --recursive",
            file=sys.stderr,
        )
        return 1

    bin_dir = resolve_bin_dir(args.bin_dir)
    prefix = resolve_prefix(bin_dir)
    print(f"Using toolchain: {bin_dir}  (prefix={prefix})")
    suites: list[tuple[str, str]] = []

    if args.tests:
        for t in args.tests:
            if (ISA / "rv64ui" / f"{t}.S").is_file():
                suites.append(("rv64ui", t))
            elif (ISA / "rv64um" / f"{t}.S").is_file():
                suites.append(("rv64um", t))
            else:
                print(f"WARNING: unknown test '{t}', skipping", file=sys.stderr)
    else:
        for t in read_manifest("manifest_rv64ui.txt"):
            suites.append(("rv64ui", t))
        for t in read_manifest("manifest_rv64um.txt"):
            suites.append(("rv64um", t))

    ok = 0
    for suite, test in suites:
        tag = f"{suite}-{test}"
        try:
            print(f"[build] {tag}")
            elf = compile_test(bin_dir, prefix, suite, test)
            hexify(elf, BUILD / tag, bin_dir)
            ok += 1
        except (subprocess.CalledProcessError, FileNotFoundError) as exc:
            print(f"[FAIL] {tag}: {exc}", file=sys.stderr)

    print(f"\nBuilt {ok}/{len(suites)} tests under {BUILD}")
    return 0 if ok == len(suites) else 1


if __name__ == "__main__":
    sys.exit(main())
