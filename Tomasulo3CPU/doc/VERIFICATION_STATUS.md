# Tomasulo3CPU — Verification Status

**Last updated:** 2026-05-28

This document describes the verification methodology, current results, known gaps, and planned work for the Tomasulo3CPU project. It is intended for design review and technical evaluation of the implementation.

---

## Overview

Tomasulo3CPU is a 64-bit out-of-order RISC-V processor (RV64IM-oriented) implemented in SystemVerilog. Verification uses a layered strategy: isolated module testbenches, full-processor directed integration tests, the official [riscv-tests](https://github.com/riscv-software-src/riscv-tests) ISA suite (subset), and bare-metal C program execution on a cycle-accurate memory model.

| Metric | Result |
|--------|--------|
| Module testbenches | 20+ blocks (`tb/*_tb.sv`) |
| Full-CPU directed tests (`CPU_tb.sv`) | 55 / 55 passing |
| Bare-metal C programs (bubble sort + c\_suite) | **8 / 8 passing** |
| riscv-tests manifest (rv64ui + rv64um) | **65 / 65 passing** |
| Synthesis (ASAP7 7nm, Design Compiler) | 250 MHz, 188K cells, timing met |

---

## Verification architecture

```
                    ┌─────────────────────────────────────┐
                    │  Layer 4: Bare-metal C programs     │
                    │  (GCC → ELF → hex → full CPU TB)    │
                    └──────────────────┬──────────────────┘
                                       │
                    ┌──────────────────▼──────────────────┐
                    │  Layer 3: riscv-tests (official)    │
                    │  arch_test/ — tohost pass/fail      │
                    └──────────────────┬──────────────────┘
                                       │
                    ┌──────────────────▼──────────────────┐
                    │  Layer 2: Full-CPU directed         │
                    │  CPU_tb.sv — hazards, CSR, traps    │
                    └──────────────────┬──────────────────┘
                                       │
                    ┌──────────────────▼──────────────────┐
                    │  Layer 1: Module-level TBs          │
                    │  ROB, FRAT, CDB, DISPATCH, …        │
                    └─────────────────────────────────────┘
```

**Simulators:** Synopsys VCS and/or Siemens QuestaSim. Synopsys DesignWare MUL/DIV IP is optional; open-source behavioral stubs (`tb/dw_ip_stubs.sv`) support flows without a DesignWare license.

**Note:** Custom directed tests in `CPU_tb.sv` are not interchangeable with the RISC-V International architectural compliance flow (riscv-arch-test / RISCOF). Both are reported separately below.

---

## Layer 1 — Module-level verification

Individual RTL blocks are exercised with dedicated self-checking testbenches under `tb/`.

| Area | Testbench |
|------|-----------|
| Fetch / decode | `IFQ_tb`, `DISPATCH_tb`, `CPU_FRONT_END_tb` |
| Rename / allocate | `FRAT_tb`, `FRL_tb`, `RRAT_tb` |
| Commit / memory ordering | `ROB_tb`, `SB_tb`, `RBA_tb` |
| Issue / execute | `ISSUEQ_tb`, `INTQ_tb`, `MULQ_tb`, `DIVQ_tb`, `LSQ_tb`, `ISSUEUNIT_tb`, `EXE_tb`, `PRF_tb` |
| Back-end integration | `CPU_BACK_END_tb` |
| Branch prediction | `BPB_tb`, `RAS_tb` |

Build and run via project `Makefile` (`make sim-questa USE_DW=0 PROJECT=<BLOCK>`).

---

## Layer 2 — Full-CPU directed integration (`CPU_tb.sv`)

### Scope

Fifty-five directed scenarios run the complete `CPU` against behavioral instruction and data memory models. Tests encode instructions programmatically and check architectural state, CSR values, and selected internal observability points.

### Instruction and feature coverage

| Category | Coverage |
|----------|----------|
| R-type / I-type ALU | ADD, SUB, AND, OR, XOR, SLT, SLTU, shifts (SLL, SRL, SRA, immediate variants) |
| M extension | MUL, DIV, REM |
| U-type | LUI, AUIPC |
| Load / store | LD, LW, SD, SW, SB, SH, LB, LBU, LH, LHU, LWU |
| Branches | BEQ, BNE, BLT, BGE, BLTU, BGEU |
| Jumps | JAL, JALR |
| Word arithmetic | ADDIW |
| CSR / traps | CSRRW, CSRRS, CSRRC, CSRRWI, ECALL, EBREAK, MRET |
| Microarchitecture | RAW / WAW hazards, ROB capacity, mixed FU interleaving, branch + RAS |

### Result

**55 / 55 passing** (QuestaSim, May 2026).

---

## Layer 3 — Software validation

### Bare-metal programs

Programs are built with a RISC-V cross-compiler (`rv64im_zicsr`, `lp64`, `-nostdlib`), converted to Verilog hex preload files, and executed on `CPU_bubble_sort_tb` or equivalent full-CPU testbenches.

| Program | Status | Testbench |
|---------|--------|-----------|
| `cprogram/bubble_sort.c` | Pass | `CPU_bubble_sort_tb` |
| `cprogram/c_suite/memcpy` | Pass | `CPU_c_suite` (tohost) |
| `cprogram/c_suite/memset` | Pass | `CPU_c_suite` (tohost) |
| `cprogram/c_suite/strlen` | Pass | `CPU_c_suite` (tohost) |
| `cprogram/c_suite/strcmp` | Pass | `CPU_c_suite` (tohost) |
| `cprogram/c_suite/matrix_multiply` | Pass | `CPU_c_suite` (tohost) |
| `cprogram/c_suite/linked_list` | Pass | `CPU_c_suite` (tohost) |
| `cprogram/c_suite/recursion` | Pass | `CPU_c_suite` (tohost) |
| `cprogram/trap_demo.c` + `trap_handler.S` | Not in regression | — |

### Official riscv-tests

The project integrates the `riscv-software-src/riscv-tests` repository under `third_party/riscv-tests`. Tests are built with a Tomasulo-specific linker script and environment header (`arch_test/`), executed on `CPU_riscv_tests_tb`, and graded by the standard **tohost** completion protocol (write `1` = pass).

| Item | Value |
|------|-------|
| Manifest | `arch_test/manifest_rv64ui.txt` (52 tests), `arch_test/manifest_rv64um.txt` (13 tests) |
| Excluded from manifest | `fence_i`, `ma_data` |
| Build / run | [arch_test/README.md](../arch_test/README.md) |
| Latest regression | **65 / 65 passed** |

All manifest tests pass, including integer memory (LB/LH/SB/SH/SW/SD), shifts, `lui`, `jalr`, W-type word ops, and full M-extension (`mul`, `mulh`, `mulhu`, `mulhsu`, `mulw`, `div`, `divu`, `divw`, `divuw`, `rem`, `remu`, `remw`, `remuw`).

Detailed pass list: [arch_test/results_latest.txt](../arch_test/results_latest.txt).

---

## Assertions and formal properties

Selected RTL blocks include SystemVerilog concurrent assertions (e.g. FRL underflow/overflow, CDB validity, LSB bounds, DIV busy). A project-wide functional coverage model and UVM environment are not yet implemented.

---

## Synthesis results

RTL synthesized with Synopsys Design Compiler (V-2023.12-SP3) using ASAP7 7nm predictive PDK (RVT, TT corner, 0.7V, 25°C).

| Metric | Value |
|--------|-------|
| Target clock period | 4.0 ns (250 MHz) |
| Worst slack | 4.81 ps (MET) |
| Total cells | 187,539 (162,996 combinational + 24,478 sequential) |
| Total cell area | 23,382 μm² |
| Buf/Inv count | 41,609 |
| Critical path | MUL valid → CDB → PRF read → ALU adder → branch compare |

Reports: `report/CPU_asap7_area.txt`, `report/CPU_asap7_timing.txt`.
Synthesis script: `script/synth_asap7.tcl`.

---

## Known limitations

| Area | Description |
|------|-------------|
| ISA scope | Manifest covers RV64IM subset only; not full privileged arch or compressed ISA |
| riscv-arch-test / RISCOF | Not integrated; compliance is via riscv-tests + directed TB, not the official arch-test framework |
| Compressed ISA | Not supported (`-march` without `C`) |
| Virtual memory / PMP | Not implemented; riscv-tests environment stubs unused CSRs |
| Self-modifying code | `fence_i` excluded from manifest |

---

## Planned verification work

| Priority | Item | Description |
|----------|------|-------------|
| 1 | `trap_demo` regression | Add ECALL handler program to software regression |
| 2 | Regression automation | Single script: recompile model + `CPU_tb` + riscv-tests + bubble_sort |
| 3 | Expand riscv-tests | Optional `rv64uf` / `rv64uc` / privilege tests as features are added |
| 4 | Additional benchmarks | Dhrystone, memcpy checksum, or similar bare-metal workloads |
| 5 | Synthesis metrics | Clock frequency and area from Design Compiler |
| 6 | SVA / coverage | ROB commit, issue-queue protocols, instruction-class functional coverage |

---

## Regression history

| Date | CPU_tb | C programs | riscv-tests | Synthesis | Notes |
|------|--------|------------|-------------|-----------|-------|
| 2026-05-26 | 55/55 | 1/1 | 27/47 | — | Initial manifest regression (QuestaSim) |
| 2026-05-27 | 55/55 | 1/1 | 47/47 | — | Full manifest pass after RTL fixes (QuestaSim) |
| 2026-05-28 | 55/55 | 8/8 | 65/65 | 250 MHz | Expanded manifests, C suite pass, synthesis complete |

---

## Related documentation

| Document | Description |
|----------|-------------|
| [README.md](../README.md) | Architecture and build overview |
| [arch_test/README.md](../arch_test/README.md) | riscv-tests build and simulation flow |
| [arch_test/results_latest.txt](../arch_test/results_latest.txt) | Machine-readable pass/fail list |
