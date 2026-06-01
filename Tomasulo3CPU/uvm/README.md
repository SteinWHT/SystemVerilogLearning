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

## Spike-Golden Bare-Metal Flow

Prepare and run one C-suite program with VCS:

```sh
python3 uvm/tools/run_baremetal_spike.py memcpy
```

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
```

The runner links programs at Spike DRAM base `0x80000000`, emits DUT-normalized `imem.hex`, `dmem.hex`, `meta.txt`, and `spike_commit_trace.txt`, then launches:

```sh
make uvm USE_DW=1 UVM_TEST=cpu_baremetal_spike_test
```

Each C program is one simulation. Merge VCS coverage after the regression with:

```sh
make uvm-cov-merge COV_INPUTS="<vdb paths>"
```
