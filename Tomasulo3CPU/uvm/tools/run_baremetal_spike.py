#!/usr/bin/env python3
from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path

UVM_TOOLS = Path(__file__).resolve().parent
UVM_DIR = UVM_TOOLS.parent
PROJ = UVM_DIR.parent
C_SUITE = PROJ / "cprogram" / "c_suite"
ARCH_TEST = PROJ / "arch_test"
BUILD_ROOT = PROJ / "build" / "uvm_baremetal"
SPIKE_DEFAULT = PROJ / "tools" / "riscv" / "bin" / "spike"

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

CLASS_UNKNOWN = 0
CLASS_ALU = 1
CLASS_LOAD = 2
CLASS_STORE = 3
CLASS_BRANCH = 4
CLASS_JUMP = 5
CLASS_MUL = 6
CLASS_DIV = 7
CLASS_WORD = 8
CLASS_SYSTEM = 9


@dataclass
class SpikeCommit:
    index: int
    pc: int
    instr: int
    rd_write: int = 0
    rd_addr: int = 0
    rd_data: int = 0
    mem_write: int = 0
    mem_addr_valid: int = 0
    mem_addr: int = 0
    mem_data: int = 0
    instr_class: int = CLASS_UNKNOWN

    def to_trace_line(self) -> str:
        return (
            f"{self.index} {self.pc:016X} {self.instr:08X} "
            f"{self.rd_write} {self.rd_addr} {self.rd_data:016X} "
            f"{self.mem_write} {self.mem_addr_valid} {self.mem_addr:016X} "
            f"{self.mem_data:016X} {self.instr_class}"
        )


def run(cmd: list[str], cwd: Path, *, capture: bool = False, timeout: int | None = None) -> subprocess.CompletedProcess[str]:
    print(f"[RUN] ({cwd}) {' '.join(cmd)}")
    return subprocess.run(
        cmd,
        cwd=cwd,
        check=True,
        text=True,
        capture_output=capture,
        timeout=timeout,
    )


def write_linker_script(path: Path, spike_base: int) -> None:
    dmem_base = spike_base + 0x400
    text = f"""OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {{
    IMEM (rx)  : ORIGIN = 0x{spike_base:016X}, LENGTH = 4K
    DMEM (rwx) : ORIGIN = 0x{dmem_base:016X}, LENGTH = 2K
}}

SECTIONS {{
    .text : {{
        *(.text.start)
        *(.text*)
    }} > IMEM

    .rodata : {{
        *(.rodata*)
    }} > IMEM

    . = ORIGIN(DMEM);

    .data : {{
        *(.data*)
        *(.sdata*)
    }} > DMEM

    .bss : {{
        *(.bss*)
        *(COMMON)
    }} > DMEM

    .tohost ALIGN(8) : {{
        *(.tohost)
    }} > DMEM

    . = ALIGN(16);
    _stack_top = ORIGIN(DMEM);

    /DISCARD/ : {{
        *(.comment)
        *(.note*)
        *(.eh_frame*)
        *(.riscv.attributes)
    }}
}}
"""
    path.write_text(text, encoding="utf-8")


def write_start_file(path: Path) -> None:
    path.write_text(
        """.section .text.start
.globl _start
_start:
    la sp, _stack_top
    call main
1:
    j 1b
""",
        encoding="utf-8",
    )


def resolve_spike(explicit: Path | None) -> Path:
    if explicit is not None:
        return explicit.resolve()
    env = os.environ.get("SPIKE")
    if env:
        return Path(env).resolve()
    if SPIKE_DEFAULT.is_file():
        return SPIKE_DEFAULT.resolve()
    found = shutil.which("spike")
    if found:
        return Path(found).resolve()
    raise RuntimeError("Spike not found. Set SPIKE=/path/to/spike or install spike on PATH.")


def nm_symbol(bin_dir: Path, prefix: str, elf: Path, symbol: str) -> int:
    out = subprocess.check_output([tool_path(bin_dir, prefix, "nm"), str(elf)], text=True)
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[2] == symbol:
            return int(parts[0], 16)
    raise RuntimeError(f"Missing symbol {symbol} in {elf}")


def build_program(test: str, bin_dir_arg: Path | None, spike_base: int) -> tuple[Path, int, int]:
    bin_dir = resolve_bin_dir(bin_dir_arg)
    prefix = resolve_prefix(bin_dir)
    cc = tool_path(bin_dir, prefix, "gcc")
    objdump = tool_path(bin_dir, prefix, "objdump")
    size = tool_path(bin_dir, prefix, "size")

    src_dir = C_SUITE / test
    out = BUILD_ROOT / test
    out.mkdir(parents=True, exist_ok=True)

    link = out / "link_spike.ld"
    start = out / "start_spike.S"
    elf = out / f"{test}.elf"
    dump = out / f"{test}.dump"
    write_linker_script(link, spike_base)
    write_start_file(start)

    cmd = [
        cc,
        "-march=rv64im",
        "-mabi=lp64",
        "-nostdlib",
        "-nostartfiles",
        "-ffreestanding",
        "-fno-builtin",
        "-mcmodel=medany",
        "-msmall-data-limit=0",
        "-O1",
        "-Wall",
        "-Wextra",
        "-Wno-unused-parameter",
        "-T",
        str(link),
        "-o",
        str(elf),
        str(start),
        str(C_SUITE / "common" / "runtime.c"),
        str(src_dir / "main.c"),
    ]
    run(cmd, src_dir)
    dump.write_text(
        subprocess.check_output([objdump, "-d", "-M", "no-aliases", str(elf)], text=True),
        encoding="utf-8",
    )
    run([size, str(elf)], src_dir)
    spike_tohost = nm_symbol(bin_dir, prefix, elf, "tohost")
    convert_elf(elf, out, bin_dir)
    dut_tohost = spike_tohost - spike_base
    (out / "meta.txt").write_text(
        "\n".join(
            [
                f"BM_TEST={test}",
                f"SPIKE_BASE=0x{spike_base:X}",
                f"SPIKE_TOHOST_ADDR=0x{spike_tohost:X}",
                f"DUT_TOHOST_ADDR=0x{dut_tohost:X}",
                "",
            ]
        ),
        encoding="utf-8",
    )
    return out, spike_tohost, dut_tohost


def classify_instr(instr: int) -> int:
    opcode = instr & 0x7F
    funct3 = (instr >> 12) & 0x7
    funct7 = (instr >> 25) & 0x7F

    if opcode == 0x03:
        return CLASS_LOAD
    if opcode == 0x23:
        return CLASS_STORE
    if opcode == 0x63:
        return CLASS_BRANCH
    if opcode in (0x6F, 0x67):
        return CLASS_JUMP
    if opcode == 0x73:
        return CLASS_SYSTEM
    if opcode in (0x1B, 0x3B):
        if funct7 == 0x01:
            return CLASS_DIV if funct3 in (4, 5, 6, 7) else CLASS_MUL
        return CLASS_WORD
    if opcode == 0x33 and funct7 == 0x01:
        return CLASS_DIV if funct3 in (4, 5, 6, 7) else CLASS_MUL
    if opcode in (0x13, 0x33, 0x37, 0x17):
        return CLASS_ALU
    return CLASS_UNKNOWN


PC_RE = re.compile(r"core\s+\d+:\s+(?:\d+\s+)?0x([0-9a-fA-F]+)\s+\(0x([0-9a-fA-F]+)\)")
RD_RE = re.compile(r"\bx\s*([0-9]+)\s+(0x[0-9a-fA-F]+)")
MEM_RE = re.compile(r"\bmem\s+(0x[0-9a-fA-F]+)\s+(0x[0-9a-fA-F]+)")


def normalize_commit(commit: SpikeCommit, spike_base: int, spike_mem_size: int) -> SpikeCommit:
    commit.pc -= spike_base
    if commit.rd_write and spike_base <= commit.rd_data < (spike_base + spike_mem_size):
        commit.rd_data -= spike_base
    if commit.mem_addr_valid:
        commit.mem_addr -= spike_base
    return commit


def parse_spike_log(log: str, spike_base: int, spike_mem_size: int, spike_tohost: int) -> list[SpikeCommit]:
    commits: list[SpikeCommit] = []
    current: SpikeCommit | None = None

    def append_current() -> bool:
        nonlocal current
        if current is None:
            return False
        current.index = len(commits)
        current.instr_class = classify_instr(current.instr)
        commits.append(normalize_commit(current, spike_base, spike_mem_size))
        done = current.mem_write and current.mem_addr_valid and current.mem_addr == (spike_tohost - spike_base)
        current = None
        return done

    def update_current_from_tail(tail: str) -> None:
        assert current is not None
        tail_no_mem = tail.split("mem", 1)[0]
        rd_match = RD_RE.search(tail_no_mem)
        if rd_match:
            current.rd_addr = int(rd_match.group(1), 10)
            current.rd_data = int(rd_match.group(2), 16)
            current.rd_write = 1 if current.rd_addr != 0 else 0
        mem_match = MEM_RE.search(tail)
        if mem_match:
            current.mem_addr = int(mem_match.group(1), 16)
            current.mem_data = int(mem_match.group(2), 16)
            current.mem_addr_valid = 1
            current.mem_write = 1

    for line in log.splitlines():
        pc_match = PC_RE.search(line)
        if pc_match:
            pc = int(pc_match.group(1), 16)
            instr = int(pc_match.group(2), 16)
            if pc < spike_base:
                current = None
                continue

            if current is not None and current.pc == pc and current.instr == instr:
                update_current_from_tail(line[pc_match.end() :])
                continue

            if append_current():
                break
            current = SpikeCommit(
                index=0,
                pc=pc,
                instr=instr,
            )
            update_current_from_tail(line[pc_match.end() :])
            continue

        mem_match = MEM_RE.search(line)
        if mem_match and current is not None:
            current.mem_addr = int(mem_match.group(1), 16)
            current.mem_data = int(mem_match.group(2), 16)
            current.mem_addr_valid = 1
            current.mem_write = 1

    if current is not None:
        append_current()
    return commits


def run_spike(test: str, out: Path, spike: Path, spike_base: int, spike_mem_size: int, spike_tohost: int, instructions: int, timeout_s: int) -> Path:
    elf = out / f"{test}.elf"
    spike_log = out / "spike.log"
    trace = out / "spike_commit_trace.txt"
    cmd = [
        str(spike),
        "--isa=rv64im",
        f"-m0x{spike_base:X}:0x{spike_mem_size:X}",
        "-l",
        "--log-commits",
        f"--instructions={instructions}",
        str(elf),
    ]
    result = run(cmd, PROJ, capture=True, timeout=timeout_s)
    log_text = result.stdout + result.stderr
    spike_log.write_text(log_text, encoding="utf-8")
    commits = parse_spike_log(log_text, spike_base, spike_mem_size, spike_tohost)
    if not commits:
        raise RuntimeError(f"No Spike commits parsed for {test}; see {spike_log}")
    if not any(c.mem_write and c.mem_addr_valid and c.mem_addr == (spike_tohost - spike_base) for c in commits):
        raise RuntimeError(f"Spike trace for {test} did not reach tohost; see {spike_log}")
    lines = [
        "# idx pc instr rd_w rd rd_data mem_w mem_addr_valid mem_addr mem_data instr_class",
        *[c.to_trace_line() for c in commits],
    ]
    trace.write_text("\n".join(lines) + "\n", encoding="utf-8")
    print(f"[TRACE] {test}: wrote {len(commits)} commits to {trace}")
    return trace


def run_uvm(test: str, out: Path, trace: Path, dut_tohost: int, spike_tohost: int, spike_base: int, args: argparse.Namespace) -> None:
    plusargs = " ".join(
        [
            f"+BM_TEST={test}",
            f"+IMEM_FILE={out / 'imem.hex'}",
            f"+DMEM_FILE={out / 'dmem.hex'}",
            f"+BM_META_FILE={out / 'meta.txt'}",
            f"+SPIKE_TRACE_FILE={trace}",
            f"+DUT_TOHOST_ADDR={dut_tohost:X}",
            f"+SPIKE_TOHOST_ADDR={spike_tohost:X}",
            f"+SPIKE_BASE={spike_base:X}",
            f"+MAX_CYCLES={args.max_cycles}",
            f"+RESET_HOLD_CYCLES={args.reset_hold_cycles}",
        ]
    )
    cmd = [
        "make",
        "uvm",
        "USE_DW=1",
        "UVM_TEST=cpu_baremetal_spike_test",
        f"COV={1 if args.coverage else 0}",
        f"COV_NAME=uvm_{test}",
        f"PLUSARGS={plusargs}",
    ]
    run(cmd, PROJ)


def main() -> int:
    parser = argparse.ArgumentParser(description="Build C-suite tests, run Spike, and launch Spike-golden UVM.")
    parser.add_argument("tests", nargs="*", help="C-suite test names or 'all'")
    parser.add_argument("--bin-dir", type=Path, default=None, help="RISC-V toolchain bin directory")
    parser.add_argument("--spike", type=Path, default=None, help="Spike executable")
    parser.add_argument("--spike-base", type=lambda s: int(s, 0), default=0x80000000)
    parser.add_argument("--spike-mem-size", type=lambda s: int(s, 0), default=0x4000)
    parser.add_argument("--spike-instructions", type=int, default=200000)
    parser.add_argument("--spike-timeout", type=int, default=60)
    parser.add_argument("--max-cycles", type=int, default=500000)
    parser.add_argument("--reset-hold-cycles", type=int, default=20)
    parser.add_argument("--coverage", action="store_true", help="Pass COV=1 to VCS make flow")
    parser.add_argument("--no-sim", action="store_true", help="Only build images and Spike trace")
    args = parser.parse_args()

    targets = args.tests or ["all"]
    if "all" in targets:
        targets = PROGRAMS
    for test in targets:
        if test not in PROGRAMS:
            raise SystemExit(f"Unknown test '{test}'. Valid tests: {', '.join(PROGRAMS)}")

    spike = resolve_spike(args.spike)
    for test in targets:
        out, spike_tohost, dut_tohost = build_program(test, args.bin_dir, args.spike_base)
        trace = run_spike(
            test,
            out,
            spike,
            args.spike_base,
            args.spike_mem_size,
            spike_tohost,
            args.spike_instructions,
            args.spike_timeout,
        )
        if not args.no_sim:
            run_uvm(test, out, trace, dut_tohost, spike_tohost, args.spike_base, args)

    print(f"\n[DONE] prepared {len(targets)} bare-metal Spike-golden test(s)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
