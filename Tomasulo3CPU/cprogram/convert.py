#!/usr/bin/env python3
"""
convert.py — Convert RISC-V objdump output to hex memory file for Tomasulo3CPU.

Reads a `riscv64-unknown-elf-objdump -d` output file, decodes each instruction,
checks if it's in the supported ISA subset, and outputs a hex file suitable for
loading into the testbench instruction memory.

Supported instructions (Tomasulo3CPU current ISA):
  R-type: ADD, SUB, AND, OR, XOR, SLT, SLTU, SLL, SRL, SRA, MUL, DIV, REM
  I-type: ADDI, ANDI, ORI, XORI, SLTI, SLTIU, SLLI, SRLI, SRAI
  Load:   LW
  Store:  SW
  Branch: BEQ, BNE
  Jump:   JAL, JALR

Usage:
  python convert.py <objdump_file> [--output <hex_file>] [--format verilog|plain]
"""

import sys
import re
import argparse
from dataclasses import dataclass
from typing import List, Tuple, Optional


# =============================================================================
# RISC-V Instruction Decoding
# =============================================================================

# Opcodes
OP_LOAD    = 0b0000011
OP_MISC_MEM= 0b0001111
OP_IMM     = 0b0010011
OP_AUIPC   = 0b0010111
OP_IMM_32  = 0b0011011
OP_STORE   = 0b0100011
OP_REG     = 0b0110011
OP_LUI     = 0b0110111
OP_REG_32  = 0b0111011
OP_BRANCH  = 0b1100011
OP_JALR    = 0b1100111
OP_JAL     = 0b1101111
OP_SYSTEM  = 0b1110011

# Funct3 for ALU
F3_ADD_SUB = 0b000
F3_SLL     = 0b001
F3_SLT     = 0b010
F3_SLTU    = 0b011
F3_XOR     = 0b100
F3_SRL_SRA = 0b101
F3_OR      = 0b110
F3_AND     = 0b111

# Funct3 for Load
F3_LB  = 0b000
F3_LH  = 0b001
F3_LW  = 0b010
F3_LD  = 0b011
F3_LBU = 0b100
F3_LHU = 0b101
F3_LWU = 0b110

# Funct3 for Store
F3_SB = 0b000
F3_SH = 0b001
F3_SW = 0b010
F3_SD = 0b011

# Funct3 for Branch
F3_BEQ  = 0b000
F3_BNE  = 0b001
F3_BLT  = 0b100
F3_BGE  = 0b101
F3_BLTU = 0b110
F3_BGEU = 0b111

# Funct7
F7_ZERO   = 0b0000000
F7_ALT    = 0b0100000
F7_MULDIV = 0b0000001

# Funct3 for M-extension (under OP_REG with F7_MULDIV)
F3_MUL    = 0b000
F3_MULH   = 0b001
F3_MULHSU = 0b010
F3_MULHU  = 0b011
F3_DIV    = 0b100
F3_DIVU   = 0b101
F3_REM    = 0b110
F3_REMU   = 0b111


@dataclass
class DecodedInstr:
    addr: int
    raw: int
    name: str
    supported: bool
    reason: str = ""


def decode_fields(instr: int) -> dict:
    """Extract all standard RISC-V instruction fields."""
    return {
        'opcode': instr & 0x7F,
        'rd':     (instr >> 7) & 0x1F,
        'funct3': (instr >> 12) & 0x7,
        'rs1':    (instr >> 15) & 0x1F,
        'rs2':    (instr >> 20) & 0x1F,
        'funct7': (instr >> 25) & 0x7F,
    }


def classify_instruction(addr: int, instr: int) -> DecodedInstr:
    """Decode a 32-bit instruction and determine if it's supported."""
    f = decode_fields(instr)
    opcode = f['opcode']
    funct3 = f['funct3']
    funct7 = f['funct7']

    # --- R-type (OP_REG) ---
    if opcode == OP_REG:
        if funct7 == F7_ZERO:
            names = {F3_ADD_SUB: "ADD", F3_SLL: "SLL", F3_SLT: "SLT",
                     F3_SLTU: "SLTU", F3_XOR: "XOR", F3_SRL_SRA: "SRL",
                     F3_OR: "OR", F3_AND: "AND"}
            if funct3 in names:
                return DecodedInstr(addr, instr, names[funct3], True)
        elif funct7 == F7_ALT:
            if funct3 == F3_ADD_SUB:
                return DecodedInstr(addr, instr, "SUB", True)
            elif funct3 == F3_SRL_SRA:
                return DecodedInstr(addr, instr, "SRA", True)
        elif funct7 == F7_MULDIV:
            names = {F3_MUL: "MUL", F3_DIV: "DIV", F3_REM: "REM"}
            unsupported_m = {F3_MULH: "MULH", F3_MULHSU: "MULHSU",
                             F3_MULHU: "MULHU", F3_DIVU: "DIVU", F3_REMU: "REMU"}
            if funct3 in names:
                return DecodedInstr(addr, instr, names[funct3], True)
            elif funct3 in unsupported_m:
                return DecodedInstr(addr, instr, unsupported_m[funct3], False,
                                    "M-extension instruction not yet implemented")
        return DecodedInstr(addr, instr, f"R-type(f3={funct3:#05b},f7={funct7:#09b})", False,
                            "Unknown R-type encoding")

    # --- I-type ALU (OP_IMM) ---
    elif opcode == OP_IMM:
        if funct3 == F3_ADD_SUB:
            return DecodedInstr(addr, instr, "ADDI", True)
        elif funct3 == F3_SLT:
            return DecodedInstr(addr, instr, "SLTI", True)
        elif funct3 == F3_SLTU:
            return DecodedInstr(addr, instr, "SLTIU", True)
        elif funct3 == F3_XOR:
            return DecodedInstr(addr, instr, "XORI", True)
        elif funct3 == F3_OR:
            return DecodedInstr(addr, instr, "ORI", True)
        elif funct3 == F3_AND:
            return DecodedInstr(addr, instr, "ANDI", True)
        elif funct3 == F3_SLL:
            return DecodedInstr(addr, instr, "SLLI", True)
        elif funct3 == F3_SRL_SRA:
            if (funct7 >> 1) == 0:
                return DecodedInstr(addr, instr, "SRLI", True)
            elif (funct7 >> 1) == 0b010000:
                return DecodedInstr(addr, instr, "SRAI", True)
        return DecodedInstr(addr, instr, f"I-ALU(f3={funct3:#05b})", False,
                            "Unknown I-type ALU encoding")

    # --- Load (OP_LOAD) ---
    elif opcode == OP_LOAD:
        load_names = {F3_LB: "LB", F3_LH: "LH", F3_LW: "LW", F3_LD: "LD",
                      F3_LBU: "LBU", F3_LHU: "LHU", F3_LWU: "LWU"}
        name = load_names.get(funct3, f"LOAD(f3={funct3})")
        supported = (funct3 == F3_LW)
        reason = "" if supported else f"{name} not implemented (only LW supported)"
        return DecodedInstr(addr, instr, name, supported, reason)

    # --- Store (OP_STORE) ---
    elif opcode == OP_STORE:
        store_names = {F3_SB: "SB", F3_SH: "SH", F3_SW: "SW", F3_SD: "SD"}
        name = store_names.get(funct3, f"STORE(f3={funct3})")
        supported = (funct3 == F3_SW)
        reason = "" if supported else f"{name} not implemented (only SW supported)"
        return DecodedInstr(addr, instr, name, supported, reason)

    # --- Branch (OP_BRANCH) ---
    elif opcode == OP_BRANCH:
        branch_names = {F3_BEQ: "BEQ", F3_BNE: "BNE", F3_BLT: "BLT",
                        F3_BGE: "BGE", F3_BLTU: "BLTU", F3_BGEU: "BGEU"}
        name = branch_names.get(funct3, f"BRANCH(f3={funct3})")
        supported = funct3 in (F3_BEQ, F3_BNE)
        reason = "" if supported else f"{name} not implemented (only BEQ/BNE supported)"
        return DecodedInstr(addr, instr, name, supported, reason)

    # --- JAL ---
    elif opcode == OP_JAL:
        return DecodedInstr(addr, instr, "JAL", True)

    # --- JALR ---
    elif opcode == OP_JALR:
        return DecodedInstr(addr, instr, "JALR", True)

    # --- LUI ---
    elif opcode == OP_LUI:
        return DecodedInstr(addr, instr, "LUI", False,
                            "LUI not implemented — needed for large constants/addresses")

    # --- AUIPC ---
    elif opcode == OP_AUIPC:
        return DecodedInstr(addr, instr, "AUIPC", False,
                            "AUIPC not implemented — needed for PC-relative addressing")

    # --- RV64 I-type word ops (OP_IMM_32) ---
    elif opcode == OP_IMM_32:
        imm32_names = {F3_ADD_SUB: "ADDIW", F3_SLL: "SLLIW", F3_SRL_SRA: "SRLIW/SRAIW"}
        name = imm32_names.get(funct3, f"IMM32(f3={funct3})")
        return DecodedInstr(addr, instr, name, False,
                            "RV64 word-size immediate op not implemented")

    # --- RV64 R-type word ops (OP_REG_32) ---
    elif opcode == OP_REG_32:
        return DecodedInstr(addr, instr, "REG32-op", False,
                            "RV64 word-size register op not implemented")

    # --- FENCE ---
    elif opcode == OP_MISC_MEM:
        return DecodedInstr(addr, instr, "FENCE", False,
                            "FENCE not implemented (treat as NOP if desired)")

    # --- SYSTEM (ECALL/EBREAK/CSR) ---
    elif opcode == OP_SYSTEM:
        imm = (instr >> 20) & 0xFFF
        if funct3 == 0:
            if imm == 0:
                return DecodedInstr(addr, instr, "ECALL", False,
                                    "ECALL not implemented")
            elif imm == 1:
                return DecodedInstr(addr, instr, "EBREAK", False,
                                    "EBREAK not implemented")
        return DecodedInstr(addr, instr, "SYSTEM/CSR", False,
                            "System/CSR instructions not implemented")

    # --- Unknown ---
    else:
        return DecodedInstr(addr, instr, f"UNKNOWN(opcode={opcode:#09b})", False,
                            "Unrecognized opcode")


# =============================================================================
# Objdump Parser
# =============================================================================

def parse_objdump(filename: str) -> List[Tuple[int, int, str]]:
    """
    Parse objdump -d output. Returns list of (address, instruction_hex, asm_text).
    Expected format:
       0:   00040113    li  sp,0x400
       4:   0080006f    j   c <main>
    """
    instructions = []
    # Match lines like: "   addr:   hexinstr    asm text"
    pattern = re.compile(r'^\s*([0-9a-fA-F]+):\s+([0-9a-fA-F]+)\s+(.*)')

    # Handle UTF-16 encoded files (common on Windows with PowerShell redirection)
    with open(filename, 'rb') as fb:
        raw = fb.read()
    if raw[:2] in (b'\xff\xfe', b'\xfe\xff'):
        text = raw.decode('utf-16')
    else:
        text = raw.decode('utf-8', errors='replace')

    for line in text.splitlines():
        m = pattern.match(line)
        if m:
            addr = int(m.group(1), 16)
            instr_hex = m.group(2)
            asm_text = m.group(3).strip()

            # Skip 16-bit compressed instructions (2 hex chars = 1 byte,
            # so 4 chars = 16-bit compressed instruction)
            if len(instr_hex) == 4:
                print(f"WARNING: Compressed (16-bit) instruction at 0x{addr:08x}: "
                      f"{instr_hex} {asm_text}")
                print("  Compressed instructions (C-extension) are NOT supported.")
                print("  Ensure compilation uses -march=rv64im (no 'c').")
                sys.exit(1)

            if len(instr_hex) == 8:
                instr_val = int(instr_hex, 16)
                instructions.append((addr, instr_val, asm_text))

    return instructions


# =============================================================================
# Output Generators
# =============================================================================

def generate_verilog_hex(instructions: List[Tuple[int, int, str]],
                         output_file: str, mem_size: int = 1024):
    """
    Generate a Verilog $readmemh compatible hex file.
    Format: one 32-bit hex word per line, optionally with @address prefix.
    """
    # Build a memory image (word-addressed)
    mem = [0] * (mem_size // 4)

    for addr, instr, asm in instructions:
        word_idx = addr // 4
        if word_idx < len(mem):
            mem[word_idx] = instr

    with open(output_file, 'w') as f:
        f.write(f"// Auto-generated from RISC-V objdump\n")
        f.write(f"// Total instructions: {len(instructions)}\n")
        for i, word in enumerate(mem):
            if word != 0:
                f.write(f"@{i:04X} {word:08X}\n")
            elif i < len(instructions):
                f.write(f"@{i:04X} {word:08X}\n")

    print(f"  Verilog hex written to: {output_file}")
    print(f"  Memory size: {mem_size} bytes ({mem_size // 4} words)")


def generate_plain_hex(instructions: List[Tuple[int, int, str]],
                       output_file: str):
    """Generate a plain hex file with address and instruction comments."""
    with open(output_file, 'w') as f:
        for addr, instr, asm in instructions:
            f.write(f"{instr:08x}  // 0x{addr:04x}: {asm}\n")
    print(f"  Plain hex written to: {output_file}")


# =============================================================================
# Main
# =============================================================================

def main():
    parser = argparse.ArgumentParser(
        description="Convert RISC-V objdump to hex for Tomasulo3CPU testbench")
    parser.add_argument("input", help="objdump -d output file (*.dump)")
    parser.add_argument("--output", "-o", default=None,
                        help="Output hex file (default: <input>_imem.hex)")
    parser.add_argument("--format", "-f", choices=["verilog", "plain"],
                        default="verilog",
                        help="Output format (default: verilog)")
    parser.add_argument("--mem-size", type=int, default=1024,
                        help="Memory size in bytes for verilog format (default: 1024)")
    parser.add_argument("--force", action="store_true",
                        help="Generate output even with unsupported instructions")

    args = parser.parse_args()

    if args.output is None:
        base = args.input.rsplit('.', 1)[0]
        args.output = f"{base}_imem.hex"

    # Parse objdump
    print(f"[1/3] Parsing objdump: {args.input}")
    instructions = parse_objdump(args.input)
    print(f"  Found {len(instructions)} instructions")

    if not instructions:
        print("ERROR: No instructions found in input file.")
        print("  Make sure to run: riscv64-unknown-elf-objdump -d <elf> > <dump>")
        sys.exit(1)

    # Decode and check each instruction
    print(f"\n[2/3] Checking ISA compatibility...")
    decoded: List[DecodedInstr] = []
    unsupported: List[DecodedInstr] = []
    supported_count = 0

    for addr, instr, asm in instructions:
        d = classify_instruction(addr, instr)
        decoded.append(d)
        if d.supported:
            supported_count += 1
        else:
            unsupported.append(d)

    # Report
    print(f"  Supported:   {supported_count}/{len(instructions)}")
    print(f"  Unsupported: {len(unsupported)}/{len(instructions)}")

    if unsupported:
        print(f"\n{'='*70}")
        print(f"  UNSUPPORTED INSTRUCTIONS FOUND")
        print(f"{'='*70}")

        # Group by instruction name for a clean summary
        from collections import Counter
        unsup_summary = Counter(d.name for d in unsupported)
        print(f"\n  Summary (instruction -> count):")
        for name, count in unsup_summary.most_common():
            print(f"    {name:12s} : {count}")

        print(f"\n  Details (first 20):")
        for d in unsupported[:20]:
            print(f"    0x{d.addr:08x}: {d.raw:08x}  {d.name:12s}  — {d.reason}")
        if len(unsupported) > 20:
            print(f"    ... and {len(unsupported) - 20} more")

        print(f"\n{'='*70}")
        print(f"  To run this program, implement the above instructions first.")
        print(f"  Priority: LUI > SD/LD > BLT/BGE > ADDIW")
        print(f"{'='*70}")

        if not args.force:
            print(f"\nERROR: Cannot generate hex — unsupported instructions present.")
            print(f"  Use --force to generate anyway (unsupported will be NOPs).")
            sys.exit(1)
        else:
            print(f"\n  --force specified: generating hex with unsupported as NOP (0x00000013)")

    # Generate output
    print(f"\n[3/3] Generating hex output: {args.output}")

    # Build final instruction list (replace unsupported with NOP if forced)
    output_instrs = []
    nop = 0x00000013  # ADDI x0, x0, 0
    for (addr, instr, asm), d in zip(instructions, decoded):
        if d.supported or args.force:
            out_instr = instr if d.supported else nop
            out_instrs.append((addr, out_instr, asm if d.supported else f"NOP (was: {d.name})"))
        else:
            out_instrs.append((addr, instr, asm))

    if args.format == "verilog":
        generate_verilog_hex(output_instrs, args.output, args.mem_size)
    else:
        generate_plain_hex(output_instrs, args.output)

    print(f"\nDone!")
    if not unsupported:
        print(f"All {len(instructions)} instructions are supported — ready for simulation!")

    return 0 if not unsupported else (0 if args.force else 1)


if __name__ == "__main__":
    sys.exit(main())
