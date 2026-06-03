#!/usr/bin/env python3

import argparse
import os
import re
import shutil
import struct
import subprocess
import sys
from pathlib import Path

UVM_TOOLS = Path(__file__).resolve().parent
UVM_DIR = UVM_TOOLS.parent
PROJ = UVM_DIR.parent
C_SUITE = PROJ / "cprogram" / "c_suite"
BUILD_ROOT = PROJ / "build" / "uvm_baremetal"
COV_ROOT = PROJ / "build" / "uvm_cov"
SPIKE_DEFAULT = PROJ / "tools" / "riscv" / "bin" / "spike"

PROGRAMS = [
    "memcpy",
    "memset",
    "strlen",
    "strcmp",
    "matrix_multiply",
    "linked_list",
    "recursion",
    "csr_trap",
    "wide_data",
    "deep_recursion",
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

TOOL_PREFIXES = (
    "riscv-none-elf-",
    "riscv64-unknown-elf-",
)

DEFAULT_BIN_DIRS = [
    Path("/opt/riscv/bin"),
    Path("/usr/local/bin"),
    Path("/usr/bin"),
]


class SpikeCommit:
    def __init__(self, index, pc, instr):
        self.index = index
        self.pc = pc
        self.instr = instr
        self.rd_write = 0
        self.rd_addr = 0
        self.rd_data = 0
        self.mem_write = 0
        self.mem_addr_valid = 0
        self.mem_addr = 0
        self.mem_data = 0
        self.instr_class = CLASS_UNKNOWN

    def to_trace_line(self):
        return (
            f"{self.index} {self.pc:016X} {self.instr:08X} "
            f"{self.rd_write} {self.rd_addr} {self.rd_data:016X} "
            f"{self.mem_write} {self.mem_addr_valid} {self.mem_addr:016X} "
            f"{self.mem_data:016X} {self.instr_class}"
        )


def run(cmd, cwd, capture=False, timeout=None):
    print(f"[RUN] ({cwd}) {' '.join(cmd)}")
    stdout = subprocess.PIPE if capture else None
    stderr = subprocess.PIPE if capture else None
    return subprocess.run(
        cmd,
        cwd=cwd,
        check=True,
        universal_newlines=True,
        stdout=stdout,
        stderr=stderr,
        timeout=timeout,
    )


def _which(name):
    found = shutil.which(name)
    return Path(found).resolve() if found else None


def _tool_in_dir(bin_dir, prefix, tool):
    candidate = bin_dir / (prefix + tool)
    return candidate if candidate.is_file() else None


def _scan_bin_dir(bin_dir):
    if not bin_dir or not bin_dir.is_dir():
        return None
    for prefix in TOOL_PREFIXES:
        if _tool_in_dir(bin_dir, prefix, "gcc") is not None:
            return prefix
    return None


def resolve_bin_dir(explicit=None):
    if explicit is not None:
        p = Path(explicit)
        if _scan_bin_dir(p):
            return p.resolve()
        raise RuntimeError("No riscv*-gcc in {0}".format(p))

    for env_key in ("RISCV_TOOLCHAIN_BIN", "RISCV_BIN", "RISCV"):
        val = os.environ.get(env_key)
        if not val:
            continue
        p = Path(val)
        if env_key == "RISCV" and p.is_dir() and (p / "bin").is_dir():
            p = p / "bin"
        if _scan_bin_dir(p):
            return p.resolve()

    for prefix in TOOL_PREFIXES:
        gcc = _which(prefix + "gcc")
        if gcc is not None:
            return gcc.parent

    for p in DEFAULT_BIN_DIRS:
        if _scan_bin_dir(p):
            return p.resolve()

    raise RuntimeError(
        "RISC-V toolchain not found. Put riscv-none-elf-* or "
        "riscv64-unknown-elf-* tools on PATH, set RISCV/RISCV_BIN/"
        "RISCV_TOOLCHAIN_BIN, or pass --bin-dir."
    )


def resolve_prefix(bin_dir):
    prefix = _scan_bin_dir(bin_dir)
    if prefix is None:
        raise RuntimeError("No supported RISC-V gcc prefix found in {0}".format(bin_dir))
    return prefix


def tool_path(bin_dir, prefix, name):
    path = bin_dir / (prefix + name)
    if not path.is_file():
        raise RuntimeError("Missing RISC-V tool: {0}".format(path))
    return str(path)


def write_linker_script(path, spike_base):
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


def write_start_file(path):
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


def resolve_spike(explicit):
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


def nm_symbol(bin_dir, prefix, elf, symbol):
    out = subprocess.check_output(
        [tool_path(bin_dir, prefix, "nm"), str(elf)],
        universal_newlines=True,
    )
    for line in out.splitlines():
        parts = line.split()
        if len(parts) >= 3 and parts[2] == symbol:
            return int(parts[0], 16)
    raise RuntimeError(f"Missing symbol {symbol} in {elf}")


def load_flat_binary(bin_path):
    data = bin_path.read_bytes()
    if len(data) % 4:
        data += b"\x00" * (4 - (len(data) % 4))
    return data


def write_imem_hex(data, out):
    lines = ["// Auto-generated from ELF (instruction-side preload)"]
    for word_idx in range(0, len(data) // 4):
        word = struct.unpack_from("<I", data, word_idx * 4)[0]
        lines.append("@{0:04X} {1:08X}".format(word_idx, word))
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")


def write_dmem_hex(data, out):
    lines = ["// Auto-generated from ELF (data-side preload)"]
    if len(data) % 8:
        data += b"\x00" * (8 - (len(data) % 8))
    for qidx in range(0, len(data) // 8):
        lo = struct.unpack_from("<I", data, qidx * 8)[0]
        hi = struct.unpack_from("<I", data, qidx * 8 + 4)[0]
        lines.append("@{0:04X} {1:08X}{2:08X}".format(qidx, hi, lo))
    out.write_text("\n".join(lines) + "\n", encoding="utf-8")


def convert_elf_local(elf, out_dir, bin_dir, prefix):
    out_dir.mkdir(parents=True, exist_ok=True)
    bin_path = out_dir / "flat.bin"
    run([tool_path(bin_dir, prefix, "objcopy"), "-O", "binary", str(elf), str(bin_path)], out_dir)
    data = load_flat_binary(bin_path)
    write_imem_hex(data, out_dir / "imem.hex")
    write_dmem_hex(data, out_dir / "dmem.hex")


def build_program(test, bin_dir_arg, spike_base):
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
        "-march=rv64im_zicsr",
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
        subprocess.check_output(
            [objdump, "-d", "-M", "no-aliases", str(elf)],
            universal_newlines=True,
        ),
        encoding="utf-8",
    )
    run([size, str(elf)], src_dir)
    spike_tohost = nm_symbol(bin_dir, prefix, elf, "tohost")
    convert_elf_local(elf, out, bin_dir, prefix)
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


def classify_instr(instr):
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


def normalize_commit(commit, spike_base, spike_mem_size):
    commit.pc -= spike_base
    if commit.mem_addr_valid:
        commit.mem_addr -= spike_base
    return commit


def parse_spike_log(log, spike_base, spike_mem_size, spike_tohost):
    commits = []
    current = None

    def append_current():
        nonlocal current
        if current is None:
            return False
        current.index = len(commits)
        current.instr_class = classify_instr(current.instr)
        commits.append(normalize_commit(current, spike_base, spike_mem_size))
        done = current.mem_write and current.mem_addr_valid and current.mem_addr == (spike_tohost - spike_base)
        current = None
        return done

    def update_current_from_tail(tail):
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


def run_spike(test, out, spike, spike_base, spike_mem_size, spike_tohost, instructions, timeout_s):
    elf = out / f"{test}.elf"
    spike_log = out / "spike.log"
    trace = out / "spike_commit_trace.txt"
    cmd = [
        str(spike),
        "--isa=rv64im_zicsr",
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


def read_generated_meta(out):
    meta = out / "meta.txt"
    values = {
        "SPIKE_BASE": None,
        "SPIKE_TOHOST_ADDR": None,
        "DUT_TOHOST_ADDR": None,
    }
    if not meta.is_file():
        raise RuntimeError("Missing generated meta file: {0}".format(meta))

    for line in meta.read_text(encoding="utf-8").splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        key = key.strip()
        value = value.strip()
        if key in values:
            values[key] = int(value, 0)

    missing = [k for k, v in values.items() if v is None]
    if missing:
        raise RuntimeError("Meta file {0} missing {1}".format(meta, ", ".join(missing)))

    return values["SPIKE_TOHOST_ADDR"], values["DUT_TOHOST_ADDR"], values["SPIKE_BASE"]


def require_generated_artifacts(test):
    out = BUILD_ROOT / test
    required = [
        out / "imem.hex",
        out / "dmem.hex",
        out / "meta.txt",
        out / "spike_commit_trace.txt",
    ]
    missing = [str(p) for p in required if not p.is_file()]
    if missing:
        raise RuntimeError(
            "Missing generated artifact(s) for {0}: {1}. "
            "Run outside Docker first: python3 uvm/tools/run_baremetal_spike.py --no-sim {0}".format(
                test, ", ".join(missing)
            )
        )
    return out, out / "spike_commit_trace.txt"


def preserve_coverage_db(test):
    src = PROJ / "build" / "uvm" / "simv.vdb"
    dst = COV_ROOT / ("uvm_{0}.vdb".format(test))

    if not src.is_dir():
        raise RuntimeError(
            "Coverage was requested, but VCS did not create {0}. "
            "Check that the run used COV=1 and that build/uvm/sim.log contains -cm options.".format(src)
        )

    COV_ROOT.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        shutil.rmtree(str(dst))
    shutil.copytree(str(src), str(dst))
    print("[COV] saved {0}".format(dst))


def clean_current_coverage_db():
    src = PROJ / "build" / "uvm" / "simv.vdb"
    if src.exists():
        shutil.rmtree(str(src))
        print("[COV] removed stale {0}".format(src))


def run_uvm(test, out, trace, dut_tohost, spike_tohost, spike_base, args):
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
    if args.coverage:
        clean_current_coverage_db()
    run(cmd, PROJ)
    if args.coverage:
        preserve_coverage_db(test)


def main():
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
    parser.add_argument("--sim-only", action="store_true", help="Use existing generated artifacts and only launch VCS")
    parser.add_argument("--arch-test", action="store_true", help="Run on pre-built arch_test/build/ ELFs instead of C-suite")
    args = parser.parse_args()

    arch_test_build = PROJ / "arch_test" / "build"
    built_tests = []
    if args.arch_test and arch_test_build.is_dir():
        for d in sorted(arch_test_build.iterdir()):
            if d.is_dir() and (d / "imem.hex").is_file() and (d / "meta.txt").is_file():
                if list(d.glob("*.elf")):
                    built_tests.append(d.name)

    if args.arch_test:
        if args.spike_mem_size == 0x4000:
            args.spike_mem_size = 0x10000

    targets = args.tests or ["all"]
    if "all" in targets:
        targets = built_tests if args.arch_test else PROGRAMS
    
    valid_tests = built_tests if args.arch_test else PROGRAMS
    for test in targets:
        if test not in valid_tests:
            raise SystemExit(f"Unknown test '{test}'. Valid tests: {', '.join(valid_tests)}")

    if args.no_sim and args.sim_only:
        raise SystemExit("--no-sim and --sim-only cannot be used together")

    if args.sim_only:
        for test in targets:
            out, trace = require_generated_artifacts(test)
            spike_tohost, dut_tohost, spike_base = read_generated_meta(out)
            run_uvm(test, out, trace, dut_tohost, spike_tohost, spike_base, args)
        print(f"\n[DONE] ran {len(targets)} generated bare-metal UVM test(s)")
        return 0

    spike = resolve_spike(args.spike)
    for test in targets:
        if args.arch_test:
            test_dir = arch_test_build / test
            out = BUILD_ROOT / test
            out.mkdir(parents=True, exist_ok=True)
            
            elf_files = list(test_dir.glob("*.elf"))
            if not elf_files:
                raise RuntimeError(f"No .elf found in {test_dir}")
            src_elf = elf_files[0]
            
            shutil.copy2(src_elf, out / f"{test}.elf")
            shutil.copy2(test_dir / "imem.hex", out / "imem.hex")
            shutil.copy2(test_dir / "dmem.hex", out / "dmem.hex")
            
            meta_text = (test_dir / "meta.txt").read_text(encoding="utf-8")
            m = re.search(r"TOHOST_ADDR=0x([0-9a-fA-F]+)", meta_text)
            if not m:
                raise RuntimeError(f"Bad meta.txt in {test_dir}")
            spike_tohost = int(m.group(1), 16)
            dut_tohost = spike_tohost - args.spike_base
            
            (out / "meta.txt").write_text(
                "\n".join([
                    f"BM_TEST={test}",
                    f"SPIKE_BASE=0x{args.spike_base:X}",
                    f"SPIKE_TOHOST_ADDR=0x{spike_tohost:X}",
                    f"DUT_TOHOST_ADDR=0x{dut_tohost:X}",
                    ""
                ]),
                encoding="utf-8"
            )
        else:
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
