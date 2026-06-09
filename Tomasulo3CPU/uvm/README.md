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

For the AXI backend, UVM uses a single **unified (von Neumann) address space**:
the L1I and L1D share one AXI SRAM and address it identically
(`ICACHE_AXI_BASE_ADDR = 0`, `AXI_IMEM_BASE_WORD = 0`). This is the standard
RISC-V model and deliberately restores I/D aliasing, so self-modifying code is
only correct when the program issues `FENCE.I` (exercising the coherence path).

To keep ordinary directed (active) tests correct without aliasing, the env
places their code from address `0` upward and relocates the LD/ST
operand-scratch pool to the upper half of D-memory (`setup_dmem_line =
imem_words/2`), the same way a real linker separates `.text` from `.data`. The
bare-metal Spike flow relies on the program's own linker script for that
separation.

### FENCE.I coherence checking (AXI only)

The AXI DUT implements RISC-V `FENCE.I` software coherence (clean the
write-back L1D, then invalidate the read-only L1I, then redirect fetch). The
UVM env observes that hardware handshake and checks it:

- `cpu_coherence_if` taps the internal handshake (`fence_i_coh_start/done`,
  the D-cache `flush_req/busy/done`, `icache_inv_all`, the D-cache backing-mem
  bus, and the ROB `fence_i_commit_flush`/redirect) via hierarchical assigns in
  `tb_top_axi`. It carries embedded SVA that enforce the ordering contract:
  clean-before-invalidate, invalidation held through completion, and that a
  `FENCE.I` never commits before coherence finished.
- `cpu_coherence_monitor` publishes one `cpu_coherence_item` per episode,
  counting clean writeback beats and clean duration.
- `cpu_coherence_scoreboard` validates ordering, that an invalidation actually
  occurred, and that writebacks happen in whole 64-byte lines, plus functional
  coverage of the dirty-line count.

These are enabled by `cpu_cfg::enable_coherence_checker` (set automatically for
the AXI top) and stay dormant on the legacy DUT. Programs that contain no
`FENCE.I` simply report zero episodes.

With the unified address space, the standard `rv64ui-fence_i` self-modifying-code
test exercises the path end to end:

```sh
python3 uvm/tools/run_baremetal_spike.py --dut axi --arch-test rv64ui-fence_i
```

It stores new instruction bytes over an executable address, runs `FENCE.I`, and
jumps there; it only passes if the D$ clean + I$ invalidate make the new bytes
visible to fetch. The coherence scoreboard should report at least one episode.

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
