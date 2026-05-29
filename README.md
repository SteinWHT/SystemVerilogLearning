# RTL Design & Verification Portfolio

SystemVerilog projects covering out-of-order CPU microarchitecture, digital design fundamentals, and verification methodology.

---

## Tomasulo3CPU — Out-of-Order RISC-V Processor (RV64IM)

The main project in this repository. A 64-bit out-of-order RISC-V CPU with Tomasulo-style dynamic scheduling, physical register renaming, checkpoint-based speculative execution, and in-order commit.

| Metric | Result |
|--------|--------|
| RTL modules | 20+ (FRAT, RRAT, ROB, FRL, PRF, issue queues, CDB, LSB, BPB, RAS, ...) |
| Directed integration tests | 55 / 55 |
| Official riscv-tests (rv64ui + rv64um) | 65 / 65 |
| Bare-metal C programs | 8 / 8 (bubble sort, matrix multiply, linked list, recursion, string ops) |
| Synthesis (ASAP7 7nm, Design Compiler) | 250 MHz, 188K cells, timing met |

Key microarchitectural features:
- 128-entry physical register file with 7-bit tags
- FRAT/RRAT register alias tables with 8-slot checkpoint array for single-cycle branch recovery
- 4 parallel issue queues (INT / MUL / DIV / LD-ST) with CDB operand wakeup
- Multi-cycle pipelined execution (4-cycle MUL, 7-cycle DIV)
- Load-store buffer with store-to-load forwarding
- 2-bit saturating-counter branch predictor with return address stack
- Machine-mode CSR access and trap handling (ECALL / EBREAK / MRET)

See [`Tomasulo3CPU/`](Tomasulo3CPU/) for full architecture documentation, build instructions, and [verification status](Tomasulo3CPU/doc/VERIFICATION_STATUS.md).

---

## BasicModules — Digital Design Building Blocks

Standalone parameterized modules with self-checking testbenches and SVA assertions.

| Module | Description |
|--------|-------------|
| [`arbiter`](BasicModules/arbiter/) | Fixed-priority and round-robin arbiters |
| [`asyncFIFO`](BasicModules/asyncFIFO/) | Asynchronous FIFO with Gray-code CDC and dual-FF synchronizers |

---

## Tools & Flows

| Category | Tools |
|----------|-------|
| Simulation | Synopsys VCS, Siemens QuestaSim |
| Synthesis | Synopsys Design Compiler (ASAP7 7nm) |
| Cross-compilation | RISC-V GCC (`rv64im_zicsr`, bare-metal) |
