#!/usr/bin/env python3
"""Locate RISC-V cross-tools (xPack, SiFive, source build) on Windows/Linux."""

from __future__ import annotations

import os
import sys
from pathlib import Path
from shutil import which

# xPack / common install locations (checked if not on PATH)
DEFAULT_BIN_DIRS: list[Path] = [
    Path(r"D:\riscv-toolchain\xpack-riscv-none-elf-gcc-14.2.0-3\bin"),
    Path(r"D:/riscv-toolchain/xpack-riscv-none-elf-gcc-14.2.0-3/bin"),
]

TOOL_PREFIXES: tuple[str, ...] = (
    "riscv-none-elf-",
    "riscv64-unknown-elf-",
)


def _exe_name(tool: str) -> str:
    return f"{tool}.exe" if sys.platform == "win32" else tool


def _tool_in_dir(bin_dir: Path, prefix: str, tool: str) -> Path | None:
    candidate = bin_dir / _exe_name(f"{prefix}{tool}")
    return candidate if candidate.is_file() else None


def _scan_bin_dir(bin_dir: Path) -> str | None:
    if not bin_dir.is_dir():
        return None
    for prefix in TOOL_PREFIXES:
        if _tool_in_dir(bin_dir, prefix, "gcc") is not None:
            return prefix
    return None


def _which_prefix(tool: str) -> str | None:
    for prefix in TOOL_PREFIXES:
        if which(_exe_name(f"{prefix}{tool}")) or which(f"{prefix}{tool}"):
            return prefix
    return None


def resolve_bin_dir(explicit: str | Path | None = None) -> Path:
    """Return directory containing riscv*-gcc."""
    if explicit is not None:
        p = Path(explicit)
        if _scan_bin_dir(p):
            return p.resolve()
        raise RuntimeError(f"No riscv*-gcc in {p}")

    for env_key in ("RISCV_TOOLCHAIN_BIN", "RISCV_BIN", "RISCV"):
        val = os.environ.get(env_key)
        if not val:
            continue
        p = Path(val)
        if env_key == "RISCV" and p.is_dir() and (p / "bin").is_dir():
            p = p / "bin"
        if _scan_bin_dir(p):
            return p.resolve()

    found = _which_prefix("gcc")
    if found:
        gcc_path = which(_exe_name(f"{found}gcc")) or which(f"{found}gcc")
        assert gcc_path is not None
        return Path(gcc_path).resolve().parent

    for default_dir in DEFAULT_BIN_DIRS:
        if _scan_bin_dir(default_dir):
            return default_dir.resolve()

    # Any xpack folder under D:\riscv-toolchain
    xpack_root = Path(r"D:\riscv-toolchain")
    if xpack_root.is_dir():
        for child in sorted(xpack_root.glob("xpack-riscv-none-elf-gcc-*/bin")):
            if _scan_bin_dir(child):
                return child.resolve()

    raise RuntimeError(
        "RISC-V toolchain not found.\n"
        "  Set PATH to your bin folder, e.g.:\n"
        "    D:\\riscv-toolchain\\xpack-riscv-none-elf-gcc-14.2.0-3\\bin\n"
        "  Or set env var (PowerShell):\n"
        "    $env:RISCV_TOOLCHAIN_BIN = "
        "'D:\\riscv-toolchain\\xpack-riscv-none-elf-gcc-14.2.0-3\\bin'\n"
        "  Then: python build_tests.py add\n"
        "  Or pass: python build_tests.py --bin-dir <path> add"
    )


def resolve_prefix(bin_dir: Path | None = None) -> str:
    directory = resolve_bin_dir(bin_dir)
    prefix = _scan_bin_dir(directory)
    assert prefix is not None
    return prefix


def tool_path(bin_dir: Path, prefix: str, name: str) -> str:
    path = bin_dir / _exe_name(f"{prefix}{name}")
    if not path.is_file():
        raise FileNotFoundError(path)
    return str(path)
