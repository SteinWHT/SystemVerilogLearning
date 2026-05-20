# Tomasulo3CPU

A 64-bit **out-of-order RISC-V CPU** using physical register renaming, a reorder buffer, and Tomasulo-style scheduling. Targets the RV64IM subset with branch prediction and speculative execution.

## Architecture Overview

![Design Overview](image/design_overview.png)

The CPU is split into a **front-end** (fetch, decode, rename, dispatch, commit) and a **back-end** (issue, execute, writeback).

### Front-End (`CPU_FRONT_END`)

| Module | Role |
|--------|------|
| **IFQ** | Instruction Fetch Queue — fetches from I-Cache, buffers decoded instructions |
| **DISPATCH** | Decodes RISC-V instructions, renames registers, dispatches to issue queues |
| **BPB** | Branch Prediction Buffer — 2-bit saturating counter predictor |
| **RAS** | Return Address Stack — predicts JALR return targets |
| **FRL** | Free Register List — supplies physical register tags on rename |
| **FRAT** | Front-end Register Alias Table — speculative arch→phys mapping with checkpoints |
| **RRAT** | Retirement Register Alias Table — committed arch→phys mapping |
| **ROB** | Reorder Buffer — tracks in-flight instructions, commits in program order |
| **SB** | Store Buffer — holds committed stores for D-Cache write-out |
| **RBA** | Ready Bit Array — tracks which physical registers have valid data |

### Back-End (`CPU_BACK_END`)

| Module | Role |
|--------|------|
| **ISSUEQ** | Issue Queues — separate queues for INT, MUL, DIV, and LD/ST operations |
| **ISSUEUNIT** | Issue Unit — arbitrates which ready instructions enter execution |
| **PRF** | Physical Register File — 128-entry, multi-ported |
| **EXE** | Execution Units — ALU (1-cycle), MUL (4-cycle), DIV (7-cycle) |
| **LSB** | Load/Store Buffer — manages memory operations and D-Cache interface |
| **CDB** | Common Data Bus — broadcasts results, wakes dependents, handles flush |

### Top-Level (`CPU`)

Combines front-end and back-end with external I-Cache and D-Cache interfaces.

## Supported Instructions (current)

| Type | Instructions |
|------|-------------|
| **R-type ALU** | ADD, SUB, AND, OR, XOR, SLT, SLTU, SLL, SRL, SRA |
| **I-type ALU** | ADDI, ANDI, ORI, XORI, SLTI, SLTIU, SLLI, SRLI, SRAI |
| **M-extension** | MUL, DIV, REM |
| **Load/Store** | LW, SW |
| **Branch** | BEQ, BNE |
| **Jump** | JAL, JALR |

## Directory Structure

```
Tomasulo3CPU/
├── src/
│   ├── CPU.sv                  # Top-level integration
│   ├── CPU_FRONT_END.sv        # Front-end pipeline
│   ├── back_end/
│   │   └── CPU_BACK_END.sv     # Back-end pipeline
│   ├── RISC_V_DECODER.sv       # Instruction decoder
│   ├── riscv_opcode_pkg.sv     # Opcode definitions
│   ├── riscv_funct_pkg.sv      # Funct3/Funct7 constants
│   ├── riscv_types_pkg.sv      # Enum types (instr_e, alu_op_e, etc.)
│   ├── BPB.sv, RAS.sv, FRL.sv, FRAT.sv, RRAT.sv
│   ├── ROB.sv, SB.sv, RBA.sv, IFQ.sv, DISPATCH.sv
│   ├── ISSUEQ.sv, ISSUEUNIT.sv, PRF.sv, EXE.sv
│   ├── LSB.sv, CDB.sv
│   └── ...
├── tb/
│   ├── CPU_tb.sv               # Full CPU integration testbench
│   ├── CPU_FRONT_END_tb.sv     # Front-end unit test
│   ├── CPU_BACK_END_tb.sv      # Back-end unit test
│   └── *_tb.sv                 # Per-module unit tests
└── image/
    └── design_overview.png
```

## Key Design Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `XLEN` / `REG_FILE_DATA_WIDTH` | 64 | Data path width (RV64) |
| `PHY_REGISTER_FILE_WIDTH` | 7 | 128 physical registers |
| `ROB_DEPTH` | 16 | Reorder buffer entries |
| `ISSUE_QUEUE_DEPTH` | 16 | Entries per issue queue |
| `FRL_SIZE` | 128 | Free list capacity |
| `NUM_CHECKPOINT` | 8 | FRAT checkpoint slots for branch recovery |
| `DIV_CYCLES` | 7 | Division latency |
| `MUL_CYCLES` | 4 | Multiplication latency |

## Key Microarchitectural Features

- **Register renaming** via FRAT + FRL eliminates WAW/WAR hazards
- **Checkpoint-based recovery** — FRAT snapshots restore on branch mispredict
- **Speculative execution** — fetches past predicted branches, flushes on mispredict
- **Out-of-order execution** — instructions issue when operands ready (CDB wakeup)
- **In-order commit** — ROB retires in program order for precise exceptions
- **Branch prediction** — 2-bit BPB + RAS for calls/returns
- **Store buffer** — decouples store commit from D-Cache write latency

## Next Steps — ISA Expansion Roadmap

Priority order to reach GCC-compilable programs (`rv64im`):

1. **LUI + AUIPC** — constant/address materialization (used in nearly every function)
2. **LD + SD** — native 64-bit memory access
3. **BLT, BGE, BLTU, BGEU** — remaining branch comparisons
4. **LB/LBU/LH/LHU/LWU/SB/SH** — byte/halfword memory access
5. **ADDIW + RV64 word ops** — 32-bit `int` arithmetic (ADDW, SUBW, SLLW, SRLW, SRAW)
6. **ECALL/EBREAK** — minimal trap handling
7. **Unsigned M-extension** — MULH, MULHU, DIVU, REMU, MULW, DIVW, etc.

After steps 1–6, simple C programs compile with:
```bash
riscv64-unknown-elf-gcc -march=rv64im -mabi=lp64 -nostdlib -O2 test.c -o test
```

## Building / Simulation

The testbench supports both VCS/FSDB and open-source (Icarus/VCD) flows:

```bash
# Example with Icarus Verilog
iverilog -g2012 -o cpu_tb \
    src/riscv_opcode_pkg.sv src/riscv_funct_pkg.sv src/riscv_types_pkg.sv \
    src/*.sv src/back_end/*.sv tb/CPU_tb.sv
vvp cpu_tb

# Example with VCS
vcs -sverilog -full64 +v2k \
    src/riscv_opcode_pkg.sv src/riscv_funct_pkg.sv src/riscv_types_pkg.sv \
    src/*.sv src/back_end/*.sv tb/CPU_tb.sv \
    -o simv && ./simv
```
