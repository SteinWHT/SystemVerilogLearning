# RISC-V Architecture Tests (riscv-tests) for Tomasulo3CPU

This directory runs the official **[riscv-software-src/riscv-tests](https://github.com/riscv-software-src/riscv-tests)** ISA suite on your CPU in simulation.

## One-time setup

```bash
cd Tomasulo3CPU/third_party/riscv-tests
git submodule update --init --recursive   # provides env/encoding.h
```

### Toolchain (xPack on Windows)

```powershell
riscv-none-elf-gcc --version
```

## Build tests

```bash
cd Tomasulo3CPU/arch_test
python build_tests.py add          # one test
python build_tests.py              # all tests in manifest_*.txt
```

Outputs: `build/rv64ui-add/imem.hex`, `dmem.hex`, `meta.txt`

## Run simulation

```bash
# After building rv64ui-add:
python run_tests.py add

# Or manually (Questa, no DesignWare):
cd ..
make sim-questa USE_DW=0 PROJECT=CPU_riscv_tests \
  PLUSARGS="+IMEM_FILE=arch_test/build/rv64ui-add/imem.hex +DMEM_FILE=arch_test/build/rv64ui-add/dmem.hex +TOHOST_ADDR=0x40 +TEST_NAME=rv64ui-add"
```

Pass criteria: test writes **1** to the `tohost` symbol (via ECALL trap handler), same as Spike HTIF.

## Manifests

| File | Suite |
|------|--------|
| `manifest_rv64ui.txt` | Integer user ISA (excludes fence_i, ma_data, word ops except addiw) |
| `manifest_rv64um.txt` | MUL / DIV / REM only |

