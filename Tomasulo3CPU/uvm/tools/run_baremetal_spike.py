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
    "matrix_cache_stress",
    "fibonacci_stress",
]

STRESS_PROGRAMS = {
    "matrix_cache_stress",
    "fibonacci_stress",
}

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


def format_exception(exc):
    if isinstance(exc, subprocess.CalledProcessError):
        return "command exited with status {0}: {1}".format(
            exc.returncode, " ".join(str(arg) for arg in exc.cmd)
        )
    if isinstance(exc, subprocess.TimeoutExpired):
        return "command timed out after {0}s: {1}".format(
            exc.timeout, " ".join(str(arg) for arg in exc.cmd)
        )
    text = str(exc).strip()
    return text if text else exc.__class__.__name__


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


def write_linker_script(path, spike_base, test):
    stress = test in STRESS_PROGRAMS
    dmem_offset = 0x4000 if stress else 0x1000
    imem_length = "16K" if stress else "4K"
    dmem_length = "48K" if stress else "4K"
    dmem_base = spike_base + dmem_offset
    text = f"""OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {{
    IMEM (rx)  : ORIGIN = 0x{spike_base:016X}, LENGTH = {imem_length}
    DMEM (rwx) : ORIGIN = 0x{dmem_base:016X}, LENGTH = {dmem_length}
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
    _stack_top = ORIGIN(DMEM) + LENGTH(DMEM);

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
    write_linker_script(link, spike_base, test)
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


def uvm_build_dir(dut):
    return PROJ / "build" / f"uvm_{dut}"


def uvm_test_log_paths(out, dut):
    log_dir = out / "logs"
    return {
        "sim": log_dir / f"uvm_{dut}_sim.log",
        "screen": log_dir / f"uvm_{dut}_screen.log",
        "compile": log_dir / f"uvm_{dut}_compile.log",
    }


def clear_current_uvm_logs(dut):
    build_dir = uvm_build_dir(dut)
    for name in ("sim.log", "sim_screen.log", "compile.log"):
        path = build_dir / name
        if path.is_file():
            path.unlink()


def preserve_uvm_logs(out, dut):
    build_dir = uvm_build_dir(dut)
    paths = uvm_test_log_paths(out, dut)
    sources = {
        "sim": build_dir / "sim.log",
        "screen": build_dir / "sim_screen.log",
        "compile": build_dir / "compile.log",
    }
    paths["sim"].parent.mkdir(parents=True, exist_ok=True)
    for kind, source in sources.items():
        destination = paths[kind]
        if destination.exists():
            destination.unlink()
        if source.is_file():
            shutil.copy2(str(source), str(destination))
    return paths


def best_uvm_log(out, dut):
    paths = uvm_test_log_paths(out, dut)
    for kind in ("sim", "screen", "compile"):
        if paths[kind].is_file():
            return paths[kind]
    return None


def analyze_uvm_log(path):
    if not path.is_file():
        return False, "simulator log was not produced"

    text = path.read_text(encoding="utf-8", errors="replace")
    severity_counts = {}
    for severity, count in re.findall(r"UVM_(ERROR|FATAL)\s*:\s*(\d+)", text):
        severity_counts[severity] = int(count)

    detail_lines = []
    for line in text.splitlines():
        stripped = line.strip()
        if (
            "[FAIL]" in stripped
            or ("UVM_ERROR" in stripped and not re.search(r"UVM_ERROR\s*:\s*\d+", stripped))
            or ("UVM_FATAL" in stripped and not re.search(r"UVM_FATAL\s*:\s*\d+", stripped))
        ):
            if stripped not in detail_lines:
                detail_lines.append(stripped)
        if len(detail_lines) == 3:
            break

    error_count = severity_counts.get("ERROR", 0)
    fatal_count = severity_counts.get("FATAL", 0)
    if error_count or fatal_count or detail_lines:
        reason = "UVM_ERROR={0} UVM_FATAL={1}".format(error_count, fatal_count)
        if detail_lines:
            reason += "; " + " | ".join(detail_lines)
        return False, reason

    if "UVM Report Summary" not in text:
        return False, "UVM report summary missing; simulation may have terminated early"

    return True, "UVM_ERROR=0 UVM_FATAL=0"


# Both the bare-metal test ("... DUT tohost=1 after 2638 cycles") and the
# constrained-random test ("tohost reached after 244 cycles ...") report the
# cycle count the same way: "after <N> cycles". Pull the last such reading so a
# trailing PASS line wins over any earlier diagnostic.
CYCLES_RE = re.compile(r"after\s+(\d+)\s+cycles")


def extract_uvm_cycles(path):
    if path is None or not path.is_file():
        return None
    text = path.read_text(encoding="utf-8", errors="replace")
    matches = CYCLES_RE.findall(text)
    if not matches:
        return None
    return int(matches[-1])


def summarize_failure(exc, log):
    reason = format_exception(exc)
    if log is None or not log.is_file():
        return reason

    if log.name.endswith("_sim.log"):
        passed, log_reason = analyze_uvm_log(log)
        if not passed and log_reason not in reason:
            return reason + "; " + log_reason
        return reason

    text = log.read_text(encoding="utf-8", errors="replace")
    details = []
    for line in reversed(text.splitlines()):
        stripped = line.strip()
        lowered = stripped.lower()
        if (
            "%error" in lowered
            or "error-" in lowered
            or "fatal" in lowered
            or "error:" in lowered
        ):
            if stripped and stripped not in details:
                details.append(stripped)
        if len(details) == 3:
            break
    if details:
        reason += "; " + " | ".join(reversed(details))
    return reason


def preserve_coverage_db(test, dut):
    src = uvm_build_dir(dut) / "simv.vdb"
    dst = COV_ROOT / ("uvm_{0}_{1}.vdb".format(dut, test))

    if not src.is_dir():
        raise RuntimeError(
            "Coverage was requested, but VCS did not create {0}. "
            "Check that the run used COV=1 and that the selected UVM build log "
            "contains -cm options.".format(src)
        )

    COV_ROOT.mkdir(parents=True, exist_ok=True)
    if dst.exists():
        shutil.rmtree(str(dst))
    shutil.copytree(str(src), str(dst))
    print("[COV] saved {0}".format(dst))


def clean_current_coverage_db(dut):
    src = uvm_build_dir(dut) / "simv.vdb"
    if src.exists():
        shutil.rmtree(str(src))
        print("[COV] removed stale {0}".format(src))


def run_uvm(test, out, trace, dut_tohost, spike_tohost, spike_base, args, max_cycles):
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
            f"+MAX_CYCLES={max_cycles}",
            f"+RESET_HOLD_CYCLES={args.reset_hold_cycles}",
        ]
    )
    cmd = [
        "make",
        "uvm",
        "USE_DW=1",
        f"UVM_DUT={args.dut}",
        "UVM_TEST=cpu_baremetal_spike_test",
        f"COV={1 if args.coverage else 0}",
        f"COV_NAME=uvm_{args.dut}_{test}",
        f"PLUSARGS={plusargs}",
    ]
    clear_current_uvm_logs(args.dut)
    if args.coverage:
        clean_current_coverage_db(args.dut)
    try:
        run(cmd, PROJ)
    finally:
        paths = preserve_uvm_logs(out, args.dut)

    passed, reason = analyze_uvm_log(paths["sim"])
    if not passed:
        raise RuntimeError("{0}; see {1}".format(reason, paths["sim"]))

    if args.coverage:
        preserve_coverage_db(test, args.dut)
    return paths


# ----------------------------------------------------------------------------
# Constrained-random regression (legacy DUT only).
#
# Unlike the C-suite flow, the constrained-random test generates its program
# inside the UVM environment (cpu_rand_program) and self-checks by polling its
# own tohost cell, so there is no Spike trace / imem.hex / dmem.hex to prepare.
# It therefore has no --no-sim "prepare" stage and is run straight through VCS.
# ----------------------------------------------------------------------------
RANDOM_TEST = "constrained_random"


def build_random_plusargs(args, max_cycles):
    parts = [
        f"+MAX_CYCLES={max_cycles}",
        f"+RESET_HOLD_CYCLES={args.reset_hold_cycles}",
    ]
    knobs = [
        ("CR_NUM_INSTR", args.cr_num_instr),
        ("CR_RAW_PCT", args.cr_raw_pct),
        ("CR_WAW_PCT", args.cr_waw_pct),
        ("CR_LOAD_USE_PCT", args.cr_load_use_pct),
        ("CR_BRANCH_CLUSTER_PCT", args.cr_branch_cluster_pct),
        ("CR_BRANCH_CLUSTER_SIZE", args.cr_branch_cluster_size),
        ("CR_DEP_WINDOW", args.cr_dep_window),
        ("CR_SEED", args.cr_seed),
    ]
    for name, value in knobs:
        if value is not None:
            parts.append(f"+{name}={value}")
    return " ".join(parts)


def run_random_uvm(out, args, max_cycles):
    out.mkdir(parents=True, exist_ok=True)
    plusargs = build_random_plusargs(args, max_cycles)
    cmd = [
        "make",
        "uvm",
        "USE_DW=1",
        f"UVM_DUT={args.dut}",
        "UVM_TEST=cpu_constrained_random_test",
        f"ENABLE_SPIKE_DPI={1 if args.enable_spike_dpi else 0}",
        f"COV={1 if args.coverage else 0}",
        f"COV_NAME=uvm_{args.dut}_{RANDOM_TEST}",
        f"PLUSARGS={plusargs}",
    ]
    clear_current_uvm_logs(args.dut)
    if args.coverage:
        clean_current_coverage_db(args.dut)
    try:
        run(cmd, PROJ)
    finally:
        paths = preserve_uvm_logs(out, args.dut)

    passed, reason = analyze_uvm_log(paths["sim"])
    if not passed:
        raise RuntimeError("{0}; see {1}".format(reason, paths["sim"]))

    if args.coverage:
        preserve_coverage_db(RANDOM_TEST, args.dut)
    return paths


def run_random_regression(args):
    out = BUILD_ROOT / RANDOM_TEST
    stage = "uvm"
    results = []
    try:
        log_paths = run_random_uvm(out, args, args.max_cycles)
        cycles = extract_uvm_cycles(log_paths["sim"])
        results.append({
            "test": RANDOM_TEST,
            "status": "PASS",
            "stage": stage,
            "log": str(log_paths["sim"]),
            "cycles": cycles,
        })
        print("[PASS] {0}; {1}log: {2}".format(
            RANDOM_TEST,
            "cycles={0}; ".format(cycles) if cycles is not None else "",
            log_paths["sim"],
        ))
    except KeyboardInterrupt:
        log = best_uvm_log(out, args.dut)
        results.append({
            "test": RANDOM_TEST,
            "status": "FAIL",
            "stage": stage,
            "reason": "interrupted by user",
            "log": str(log) if log else "",
        })
        print_regression_summary(results, args.dut, False)
        return 130
    except Exception as exc:
        log = best_uvm_log(out, args.dut)
        result = {
            "test": RANDOM_TEST,
            "status": "FAIL",
            "stage": stage,
            "reason": summarize_failure(exc, log),
            "log": str(log) if log else "",
        }
        results.append(result)
        print("[FAIL] {0} stage={1}: {2}".format(RANDOM_TEST, stage, result["reason"]))
        if log:
            print("       log: {0}".format(log))

    failed = print_regression_summary(results, args.dut, False)
    write_cycles_report(results, args.dut)
    return 1 if failed else 0


def print_regression_summary(results, dut, no_sim):
    passed = sum(1 for result in results if result["status"] == "PASS")
    prepared = sum(1 for result in results if result["status"] == "PREPARED")
    failed = sum(1 for result in results if result["status"] == "FAIL")
    lines = [
        "",
        "=" * 78,
        "Bare-metal regression summary: DUT={0}".format(dut),
        "=" * 78,
    ]

    for result in results:
        line = "[{0:8}] {1}".format(result["status"], result["test"])
        if result.get("stage"):
            line += " stage={0}".format(result["stage"])
        lines.append(line)
        if result.get("reason"):
            lines.append("           {0}".format(result["reason"]))
        if result.get("log"):
            lines.append("           log: {0}".format(result["log"]))

    lines.extend(
        [
            "-" * 78,
            "Total={0} Passed={1} Prepared={2} Failed={3}".format(
                len(results), passed, prepared, failed
            ),
        ]
    )
    if failed:
        lines.append("Failed tests: {0}".format(
            ", ".join(result["test"] for result in results if result["status"] == "FAIL")
        ))
    elif no_sim:
        lines.append("All requested test artifacts were prepared successfully.")
    else:
        lines.append("All requested simulations passed.")

    summary_path = BUILD_ROOT / "regression_summary_{0}.txt".format(dut)
    summary_path.parent.mkdir(parents=True, exist_ok=True)
    summary_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    lines.append("Summary file: {0}".format(summary_path))
    print("\n".join(lines))
    return failed


def write_cycles_report(results, dut):
    """Emit 'cycles_<dut>.txt': one '<test> <cycles>' line per simulated test.

    Only tests that ran to tohost (a recorded cycle count) are listed; build- or
    artifact-stage failures and prepare-only (--no-sim) runs have no cycle number.
    """
    rows = [
        (result["test"], result["cycles"])
        for result in results
        if result.get("cycles") is not None
    ]
    if not rows:
        return None

    report_path = BUILD_ROOT / "cycles_{0}.txt".format(dut)
    report_path.parent.mkdir(parents=True, exist_ok=True)
    report_path.write_text(
        "".join("{0} {1}\n".format(test, cycles) for test, cycles in rows),
        encoding="utf-8",
    )
    print("[CYCLES] wrote {0} ({1} test(s))".format(report_path, len(rows)))
    return report_path


def main():
    parser = argparse.ArgumentParser(
        description="Build C-suite tests, run Spike, and launch Spike-golden UVM. "
                    "With --random, instead run the self-checking constrained-random "
                    "UVM test on the legacy DUT (no Spike trace / C build needed)."
    )
    parser.add_argument("tests", nargs="*", help="C-suite test names or 'all'")
    parser.add_argument("--bin-dir", type=Path, default=None, help="RISC-V toolchain bin directory")
    parser.add_argument("--spike", type=Path, default=None, help="Spike executable")
    parser.add_argument("--spike-base", type=lambda s: int(s, 0), default=0x80000000)
    parser.add_argument("--spike-mem-size", type=lambda s: int(s, 0), default=0x4000)
    parser.add_argument("--spike-instructions", type=int, default=200000)
    parser.add_argument("--spike-timeout", type=int, default=60)
    parser.add_argument("--max-cycles", type=int, default=1000000)
    parser.add_argument("--reset-hold-cycles", type=int, default=20)
    parser.add_argument(
        "--dut",
        choices=("legacy", "axi"),
        default="legacy",
        help="Select CPU_L1DCache (legacy) or CPU_L1DCache_AXI (axi)",
    )
    parser.add_argument(
        "--random",
        action="store_true",
        help="Run the constrained-random UVM test (cpu_constrained_random_test) "
             "instead of the C-suite. Legacy DUT only.",
    )
    parser.add_argument(
        "--enable-spike-dpi",
        action="store_true",
        help="With --random, build/link the Spike DPI-C co-sim (ENABLE_SPIKE_DPI=1) "
             "for lockstep checking. Requires libspike_cosim.so in the VCS environment.",
    )
    parser.add_argument("--cr-num-instr", type=int, default=None, help="[--random] body instruction count")
    parser.add_argument("--cr-seed", type=int, default=None, help="[--random] generator seed")
    parser.add_argument("--cr-raw-pct", type=int, default=None, help="[--random] RAW dependency density %%")
    parser.add_argument("--cr-waw-pct", type=int, default=None, help="[--random] WAW reuse density %%")
    parser.add_argument("--cr-load-use-pct", type=int, default=None, help="[--random] load-use density %%")
    parser.add_argument("--cr-branch-cluster-pct", type=int, default=None, help="[--random] branch-cluster probability %%")
    parser.add_argument("--cr-branch-cluster-size", type=int, default=None, help="[--random] branches per cluster")
    parser.add_argument("--cr-dep-window", type=int, default=None, help="[--random] producer look-back window")
    parser.add_argument("--coverage", action="store_true", help="Pass COV=1 to VCS make flow")
    parser.add_argument(
        "--merge-cov",
        action="store_true",
        help="After sims, run make uvm-cov-merge-baremetal (C-suite vdbs only; avoids stale arch-test shapes)",
    )
    parser.add_argument("--no-sim", action="store_true", help="Only build images and Spike trace")
    parser.add_argument("--sim-only", action="store_true", help="Use existing generated artifacts and only launch VCS")
    parser.add_argument("--arch-test", action="store_true", help="Run on pre-built arch_test/build/ ELFs instead of C-suite")
    parser.add_argument(
        "--fail-fast",
        action="store_true",
        help="Stop after the first failed test instead of completing the regression",
    )
    args = parser.parse_args()

    if args.random:
        if args.dut != "legacy":
            raise SystemExit("--random runs on the legacy DUT only; pass --dut legacy (the default)")
        if args.no_sim:
            raise SystemExit("--random has no build artifacts to prepare; drop --no-sim")
        if args.arch_test:
            raise SystemExit("--random and --arch-test are mutually exclusive")
        return run_random_regression(args)

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

    results = []
    spike = None if args.sim_only else resolve_spike(args.spike)
    for test in targets:
        out = BUILD_ROOT / test
        stage = "setup"
        spike_mem_size = args.spike_mem_size
        spike_instructions = args.spike_instructions
        spike_timeout = args.spike_timeout
        max_cycles = args.max_cycles
        if test in STRESS_PROGRAMS:
            if spike_mem_size == 0x4000:
                spike_mem_size = 0x10000
            if spike_instructions == 200000:
                spike_instructions = 600000
            if spike_timeout == 60:
                spike_timeout = 180
            if max_cycles == 1000000:
                max_cycles = 3000000

        try:
            if args.sim_only:
                stage = "artifacts"
                out, trace = require_generated_artifacts(test)
                spike_tohost, dut_tohost, spike_base = read_generated_meta(out)
            else:
                stage = "build"
                if args.arch_test:
                    test_dir = arch_test_build / test
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
                    out, spike_tohost, dut_tohost = build_program(
                        test, args.bin_dir, args.spike_base
                    )

                stage = "spike"
                trace = run_spike(
                    test,
                    out,
                    spike,
                    args.spike_base,
                    spike_mem_size,
                    spike_tohost,
                    spike_instructions,
                    spike_timeout,
                )

            if args.no_sim:
                results.append({
                    "test": test,
                    "status": "PREPARED",
                    "stage": "artifacts",
                })
                print("[PREPARED] {0}".format(test))
                continue

            stage = "uvm"
            log_paths = run_uvm(
                test, out, trace, dut_tohost, spike_tohost,
                args.spike_base if not args.sim_only else spike_base,
                args, max_cycles
            )
            cycles = extract_uvm_cycles(log_paths["sim"])
            results.append({
                "test": test,
                "status": "PASS",
                "stage": stage,
                "log": str(log_paths["sim"]),
                "cycles": cycles,
            })
            print("[PASS] {0}; {1}log: {2}".format(
                test,
                "cycles={0}; ".format(cycles) if cycles is not None else "",
                log_paths["sim"],
            ))
        except KeyboardInterrupt:
            log = best_uvm_log(out, args.dut)
            results.append({
                "test": test,
                "status": "FAIL",
                "stage": stage,
                "reason": "interrupted by user",
                "log": str(log) if log else "",
            })
            print_regression_summary(results, args.dut, args.no_sim)
            return 130
        except Exception as exc:
            log = best_uvm_log(out, args.dut)
            result = {
                "test": test,
                "status": "FAIL",
                "stage": stage,
                "reason": summarize_failure(exc, log),
                "log": str(log) if log else "",
            }
            results.append(result)
            print("[FAIL] {0} stage={1}: {2}".format(
                test, stage, result["reason"]
            ))
            if log:
                print("       log: {0}".format(log))
            if args.fail_fast:
                break

    if args.merge_cov:
        if any(result["status"] == "FAIL" for result in results):
            print("[WARN] Skipping coverage merge because the regression has failures")
        else:
            try:
                if not args.coverage:
                    print("[WARN] --merge-cov without --coverage: merging existing vdbs only")
                run(["make", "uvm-cov-merge-baremetal", f"COV_DUT={args.dut}"], PROJ)
            except Exception as exc:
                results.append({
                    "test": "coverage_merge",
                    "status": "FAIL",
                    "stage": "coverage",
                    "reason": format_exception(exc),
                })

    failed = print_regression_summary(results, args.dut, args.no_sim)
    write_cycles_report(results, args.dut)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
