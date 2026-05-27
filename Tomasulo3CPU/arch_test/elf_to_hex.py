#!/usr/bin/env python3
"""
Convert a bare-metal RISC-V ELF (riscv-tests) into Tomasulo3CPU hex preload files.

Outputs under arch_test/build/<test_name>/:
  imem.hex   — 32-bit instruction words (@word_index)
  dmem.hex   — 64-bit data words (@qword_index) for load/store
  meta.txt   — TOHOST_ADDR=<hex>  (byte address of tohost symbol)
"""

from __future__ import annotations

import argparse
import re
import struct
import subprocess
import sys
from pathlib import Path

from riscv_toolchain import resolve_bin_dir, resolve_prefix, tool_path


def run(cmd: list[str]) -> str:
    result = subprocess.run(cmd, check=True, capture_output=True, text=True)
    return result.stdout


def parse_tohost_addr(bin_dir: Path, prefix: str, elf: Path) -> int:
    out = run([tool_path(bin_dir, prefix, "nm"), str(elf)])
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[2] == "tohost":
            return int(parts[0], 16)
    raise RuntimeError(f"Symbol 'tohost' not found in {elf}")


def load_flat_binary(bin_path: Path) -> bytes:
    data = bin_path.read_bytes()
    if len(data) % 4:
        data += b"\x00" * (4 - (len(data) % 4))
    return data


def write_imem_hex(data: bytes, out: Path) -> None:
    lines = ["// Auto-generated from ELF (instruction-side preload)"]
    for word_idx in range(0, len(data) // 4, 1):
        w = struct.unpack_from("<I", data, word_idx * 4)[0]
        lines.append(f"@{word_idx:04X} {w:08X}")
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_dmem_hex(data: bytes, out: Path) -> None:
    lines = ["// Auto-generated from ELF (data-side preload)"]
    if len(data) % 8:
        data += b"\x00" * (8 - (len(data) % 8))
    for qidx in range(0, len(data) // 8):
        lo = struct.unpack_from("<I", data, qidx * 8)[0]
        hi = struct.unpack_from("<I", data, qidx * 8 + 4)[0]
        lines.append(f"@{qidx:04X} {hi:08X}{lo:08X}")
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")


def convert_elf(elf: Path, out_dir: Path, bin_dir: Path | None = None) -> int:
    out_dir.mkdir(parents=True, exist_ok=True)
    toolchain_bin = resolve_bin_dir(bin_dir)
    prefix = resolve_prefix(toolchain_bin)
    bin_path = out_dir / "flat.bin"
    run([tool_path(toolchain_bin, prefix, "objcopy"), "-O", "binary", str(elf), str(bin_path)])
    tohost = parse_tohost_addr(toolchain_bin, prefix, elf)
    data = load_flat_binary(bin_path)
    write_imem_hex(data, out_dir / "imem.hex")
    write_dmem_hex(data, out_dir / "dmem.hex")
    (out_dir / "meta.txt").write_text(f"TOHOST_ADDR=0x{tohost:X}\n", encoding="utf-8")
    return tohost


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("elf", type=Path, help="Input ELF file")
    parser.add_argument(
        "-o",
        "--output-dir",
        type=Path,
        required=True,
        help="Output directory for hex/meta files",
    )
    parser.add_argument(
        "--bin-dir",
        type=Path,
        default=None,
        help="Toolchain bin directory",
    )
    args = parser.parse_args()
    tohost = convert_elf(args.elf, args.output_dir, args.bin_dir)
    print(f"Wrote {args.output_dir} (tohost=0x{tohost:X})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
