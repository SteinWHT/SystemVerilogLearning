# Bare-metal C Suite (RV64IM)

This suite adds small bare-metal C programs for:

- `memcpy`
- `memset`
- `strlen`
- `strcmp`
- `matrix_multiply`
- `linked_list`
- `recursion`

Each program is self-checking and writes to `tohost`:

- `tohost = 1` -> PASS
- `tohost != 1` -> FAIL code

## Build

Build all:

`python cprogram/c_suite/build_suite.py`

Build a subset:

`python cprogram/c_suite/build_suite.py memcpy strcmp`

Artifacts are generated under `cprogram/c_suite/build/<test>/`:

- `<test>.elf`
- `<test>.dump`
- `imem.hex`
- `dmem.hex`
- `meta.txt` (`TOHOST_ADDR=...`)

## Run (single configurable TB)

Run all with Questa flow:

`python cprogram/c_suite/run_suite.py`

Run subset:

`python cprogram/c_suite/run_suite.py matrix_multiply recursion`

This uses `PROJECT=CPU_c_suite` and passes:

- `+IMEM_FILE=...`
- `+DMEM_FILE=...`
- `+TOHOST_ADDR=...`
- `+TEST_NAME=...`

## Coverage Notes

Programs call shared RV64IM exercise helpers in `common/common.h` to force use of:

- `mulh`, `mulhu`, `mulhsu`, `mulw`
- `divw`, `divuw`, `remw`, `remuw`
- mixed load/store widths and sign/zero-extension behavior
- branch and shift-heavy integer control/data flow
