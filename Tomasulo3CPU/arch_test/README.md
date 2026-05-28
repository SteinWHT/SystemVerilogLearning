# RISC-V Architecture Tests (riscv-tests) for Tomasulo3CPU

This directory runs the official **[riscv-software-src/riscv-tests](https://github.com/riscv-software-src/riscv-tests)** ISA suite on the full CPU in simulation.

**Status (manifest regression):** **47 / 47 passing** (44× `rv64ui` + 3× `rv64um`, QuestaSim, May 2026). See [doc/VERIFICATION_STATUS.md](../doc/VERIFICATION_STATUS.md) for the full verification picture.

## One-time setup

```bash
cd Tomasulo3CPU/third_party/riscv-tests
git submodule update --init --recursive   # provides env/encoding.h
```

### Toolchain (xPack on Windows)

Install [xPack RISC-V GCC](https://github.com/xpack-dev-tools/riscv-none-elf-gcc-xpack) and ensure `riscv-none-elf-gcc` is on `PATH`, or pass `--bin-dir`:

```powershell
python build_tests.py --bin-dir "D:\riscv-toolchain\xpack-riscv-none-elf-gcc-14.2.0-3\bin"
```

## Build tests

```bash
cd Tomasulo3CPU/arch_test
python build_tests.py add          # one test
python build_tests.py              # all tests in manifest_*.txt
```

Outputs per test directory (`build/rv64ui-add/`):

| File | Description |
|------|-------------|
| `*.elf` | Linked test program |
| `imem.hex`, `dmem.hex` | Simulation preload |
| `meta.txt` | `TOHOST_ADDR` (typically `0x100`) |
| `*.dump` | Optional: `python gen_dumps.py add` or `gen_dumps.py rv64ui-add` |

## Compile simulation model (Questa)

**Recompile after any RTL or testbench change.** `run_tests.py` does not run `vlog` automatically.

### Linux / WSL (recommended)

```bash
cd Tomasulo3CPU
make sim-questa USE_DW=0 PROJECT=CPU_riscv_tests
```

This runs `vlog` on all RTL + `CPU_riscv_tests_tb` and leaves the library in `build/questa_CPU_riscv_tests/work`.

### Windows (no `make`)

Set `QUESTA_BIN` (or add Questa to `PATH`), then run `vlib` + `vlog` from `build/questa_CPU_riscv_tests` with the same source list as the `sim-questa` target in the project `Makefile` (`USE_DW=0`, packages first, then `tb/dw_ip_stubs.sv`, then remaining `src/` files, then `tb/CPU_riscv_tests_tb.sv`). Re-run `vlog` after every RTL change before `run_tests.py`.

## Run regression

```bash
cd Tomasulo3CPU/arch_test
python run_tests.py              # all built tests (Questa by default)
python run_tests.py add jalr     # subset by short name
python run_tests.py --sim vcs    # Linux: VCS via make sim
```

Pass criteria: program writes **1** to the `tohost` symbol (ECALL trap handler), same as Spike HTIF. Odd `tohost` ≠ 1 indicates a failing sub-test (`gp` encoded).

### Manual Questa run (one test)

```powershell
cd Tomasulo3CPU\build\questa_CPU_riscv_tests
vsim -c -do "run -all; quit -f" CPU_riscv_tests_tb `
  "+IMEM_FILE=D:/.../arch_test/build/rv64ui-add/imem.hex" `
  "+DMEM_FILE=D:/.../arch_test/build/rv64ui-add/dmem.hex" `
  "+TOHOST_ADDR=100" `
  "+TEST_NAME=rv64ui-add"
```

Use forward slashes in hex paths on Windows. Read `TOHOST_ADDR` from each test’s `meta.txt`.

## Manifests

| File | Suite |
|------|--------|
| `manifest_rv64ui.txt` | Integer user ISA (44 tests) |
| `manifest_rv64um.txt` | MUL / DIV / REM (3 tests) |

Excluded from manifest (not implemented or out of scope): `fence_i`, `ma_data`, RV64 `*w` word ops except `addiw`.

## Utilities

| Script | Purpose |
|--------|---------|
| `gen_dumps.py` | `objdump -d` next to each built ELF |
| `riscv_toolchain.py` | Auto-detect xPack / SiFive toolchain |

Pass/fail log: [results_latest.txt](results_latest.txt).
