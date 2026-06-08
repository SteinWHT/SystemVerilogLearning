# Tomasulo3CPU UVM

## Layout

- `agent/` CPU stimulus, commit monitor, and dcache monitor
- `env/` UVM environment and configuration
- `items/` sequence/monitor transactions
- `seq/` directed instruction sequences
- `tests/` UVM tests
- `scoreboard/` directed and Spike-golden scoreboards
- `ref/` reference-model hooks
- `cov/` functional coverage
- `utils/` shared types, parameters, encoders, and setup helpers
- `tools/` regression helpers

## DUT Backends

The same UVM package, tests, agents, D-cache scoreboard, and Spike flow support:

- `legacy`: `CPU_L1DCache` with the direct cache backing memory
- `axi`: `CPU_L1DCache_AXI` with the AXI4 bridge, 2x1 fabric, and AXI SRAM

The shared `cpu_if` selects the correct preload port while keeping one
architectural shadow memory for scoreboards and `tohost` polling.

For the AXI backend, UVM keeps instruction and data storage independent:

- D-memory occupies SRAM word indices `0` through `16383`.
- I-memory starts at SRAM word index `32768` (byte address `0x40000`).
- L1I translates CPU fetch addresses into the I-memory window; L1D addresses
  remain unchanged.

This avoids requiring I/D cache coherency when directed tests preload operands
and instructions at the same CPU-visible address.

Compile or run the legacy system:

```sh
make uvm-compile UVM_TEST=cpu_baremetal_spike_test
make uvm UVM_TEST=cpu_baremetal_spike_test
```

Compile or run the AXI system:

```sh
make uvm-axi-compile UVM_TEST=cpu_baremetal_spike_test
make uvm-axi UVM_TEST=cpu_baremetal_spike_test
```

The generic form is `make uvm UVM_DUT=legacy|axi`. Separate build directories
(`build/uvm_legacy` and `build/uvm_axi`) prevent stale elaboration artifacts
from crossing between the two DUTs. Every test fails on the AXI bridge's sticky
error status and reports D-cache hit/miss statistics.

## Spike-Golden Bare-Metal Flow

Prepare and run one C-suite program with VCS:

```sh
python3 uvm/tools/run_baremetal_spike.py memcpy
```

Run the same program against the AXI-backed system:

```sh
python3 uvm/tools/run_baremetal_spike.py --dut axi memcpy
```

Full regressions continue after individual failures and finish with a compact
pass/fail table:

```sh
python3 uvm/tools/run_baremetal_spike.py --dut axi all
```

The table is also saved as `build/uvm_baremetal/regression_summary_axi.txt`
(`..._legacy.txt` for the legacy DUT). Per-test simulator, screen, and compile
logs are preserved under `build/uvm_baremetal/<test>/logs/`, so later tests do
not overwrite the evidence from an earlier failure. The process exits with
status 1 when any test fails. Add `--fail-fast` to retain the old stop-on-first-
failure behavior.

Prepare all C-suite programs and run each as a separate UVM simulation:

```sh
python3 uvm/tools/run_baremetal_spike.py all
```

Generate Spike traces and hex images without launching VCS:

```sh
python3 uvm/tools/run_baremetal_spike.py --no-sim all
```

Enable VCS coverage names per program:

```sh
python3 uvm/tools/run_baremetal_spike.py --coverage all
python3 uvm/tools/run_baremetal_spike.py --dut axi --coverage all
```

The runner links programs at Spike DRAM base `0x80000000`, emits DUT-normalized `imem.hex`, `dmem.hex`, `meta.txt`, and `spike_commit_trace.txt`, then launches:

```sh
make uvm USE_DW=1 UVM_TEST=cpu_baremetal_spike_test
```

Each C program is one simulation. Merge VCS coverage after the regression with:

```sh
make uvm-cov-merge-baremetal COV_DUT=legacy
make uvm-cov-merge-baremetal COV_DUT=axi
```
