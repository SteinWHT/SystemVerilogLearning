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
- `dpi/` SystemVerilog import package for the Spike DPI-C co-sim
- `tools/` regression helpers and the `spike_cosim/` C++ DPI shim

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

## Constrained-Random Flow (DPI-C Spike co-simulation)

`cpu_constrained_random_test` exercises the CPU with a procedurally generated
RV64IM + Zicsr program of *configurable hazard density* and checks every commit
in lockstep against Spike running as an in-process golden model over DPI-C. No
external trace files are produced: the DUT and Spike step the identical image
together and the scoreboard compares architectural state instruction by
instruction.

### Pieces

- `utils/cpu_isa_encoder.sv` — single source of truth for RV64IM+Zicsr encoding
  (opcode/funct3/funct7, instruction format, operand usage, access width).
- `items/cpu_instr_item.sv` — a fully-resolved generic instruction item; the
  encoder fixes the 32-bit word so the IMEM image and Spike see the same bytes.
- `seq/cpu_rand_program.sv` — the generator. It emits a prologue (data pointer +
  seeded GPRs), a weighted-random body, and a `tohost` epilogue. Control flow is
  forward-only by construction, which guarantees termination.
- `seq/cpu_rand_program_seq.sv` — streams the generated stream to the driver.
- `tools/spike_cosim/` — the C++ DPI shim that wraps a Spike `processor_t` over a
  flat memory `simif_t` (no MMIO), with `dpi/cpu_spike_dpi_pkg.sv` exposing it.
- `scoreboard/cpu_spike_dpi_scoreboard.sv` — preloads Spike with the program +
  data and compares PC, register writes, and store addresses each commit.
- `cov/cpu_hazard_coverage.sv` — opcode/class mix plus hazard-kind and
  producer-distance coverage.

### Hazard knobs

All percentages are `0..100` and overridable on the command line:

| Plusarg | `cpu_cfg` field | Meaning |
| --- | --- | --- |
| `+CR_NUM_INSTR=<n>` | `cr_num_instr` | body instruction count |
| `+CR_RAW_PCT=<p>` | `cr_raw_pct` | RAW source-dependency density |
| `+CR_WAW_PCT=<p>` | `cr_waw_pct` | WAW destination-reuse density |
| `+CR_LOAD_USE_PCT=<p>` | `cr_load_use_pct` | load-use density |
| `+CR_BRANCH_CLUSTER_PCT=<p>` | `cr_branch_cluster_pct` | chance to open a branch cluster |
| `+CR_BRANCH_CLUSTER_SIZE=<n>` | `cr_branch_cluster_size` | branches per cluster |
| `+CR_DEP_WINDOW=<n>` | `cr_dep_window` | producer look-back window |
| `+CR_SEED=<n>` | — | generator seed (`srandom`) for reproducibility |

### Build and run

The DPI-C path is opt-in. Build Spike under `tools/riscv-isa-sim` (its libraries
are expected in `tools/riscv-isa-sim/build`, overridable via `SPIKE_SRC_DIR` /
`SPIKE_LIB_DIR`) and set `ENABLE_SPIKE_DPI=1`; the Makefile compiles
`tools/spike_cosim/spike_cosim.cc`, links it against the Spike libraries, and
defines `CPU_SPIKE_DPI` so the DPI package, scoreboard, and env wiring are
included:

```sh
make uvm-compile ENABLE_SPIKE_DPI=1 UVM_TEST=cpu_constrained_random_test
make uvm ENABLE_SPIKE_DPI=1 UVM_TEST=cpu_constrained_random_test \
  PLUSARGS="+CR_NUM_INSTR=400 +CR_RAW_PCT=60 +CR_WAW_PCT=30 \
            +CR_LOAD_USE_PCT=40 +CR_BRANCH_CLUSTER_PCT=20 +CR_SEED=1"
```

The shim is C++17. If the default `g++` is too old (it rejects `-std=c++17`),
point `CXX` at the C++17 compiler that built Spike — ideally the *same* one, to
keep the libstdc++ ABI consistent:

```sh
make spike-cosim-lib ENABLE_SPIKE_DPI=1 CXX=g++-9
```

`SPIKE_CXXSTD` overrides the standard flag for compilers that only know the
older spelling (`SPIKE_CXXSTD=c++1z`). Set `SPIKE_COSIM_LOG=<file>` to capture
Spike's commit log (it defaults to `/dev/null`). Without `ENABLE_SPIKE_DPI=1`
the package compiles unchanged and the DPI components are simply excluded.

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
