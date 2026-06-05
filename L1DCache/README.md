# L1DCache — L1 Data Cache for Tomasulo3CPU

Standalone **L1 D-cache**: RTL, directed testbenches, and a Tomasulo integration wrapper for the [Tomasulo3CPU](../Tomasulo3CPU/) out-of-order RISC-V core.

---

## Status

| Item | State |
|------|--------|
| Plan | [`doc/L1_DCACHE_PLAN.md`](doc/L1_DCACHE_PLAN.md) |
| Microarch | [`doc/DCACHE_MICROARCH.md`](doc/DCACHE_MICROARCH.md) |
| RTL | **Complete** — core, MSHR, burst refill/writeback, PLRU, tag/data RAM |
| Module tests | `dcache_plru_tb`, `dcache_core_tb` |
| Tomasulo hookup | **Integrated** through [`Tomasulo3CPU/src/CPU_L1DCache.sv`](../Tomasulo3CPU/src/CPU_L1DCache.sv) |
| Full CPU test | Bare-metal C and RISC-V tests through Spike-golden UVM |
| UVM checking | Read data, byte-strobe stores, request/response completion, and pending transactions |
| Coverage | Per-test VCS databases for C-suite and RISC-V tests, mergeable with URG |

### Features

- 16 KiB, 4-way set-associative, **64-byte lines**, write-back, write-allocate  
- 64-bit word CPU access with byte strobe and correct word-within-line select/merge  
- Tree PLRU replacement, lowest-invalid-way allocation, single MSHR  
- **8-beat burst** refill and dirty writeback over a 64-bit memory bus  
- Split load/store valid/ready ports (`dcache_if` / `dcache_top`)  
- Hit/miss statistics on `dcache_top`  
- All geometry derived from `dcache_pkg.sv` (retarget by changing a few localparams)

---

## Simulate

```bash
cd L1DCache
make sim PROJECT=dcache_plru    # PLRU golden check
make sim PROJECT=dcache_core    # full cache directed tests
```

Questa/VCS are used automatically if `vlog`/`vcs` is on `PATH`. For SVA bind checks:

```bash
make sim PROJECT=dcache_core USE_SVA=1   # requires Questa or VCS
```

---

## RTL map

| File | Role |
|------|------|
| `rtl/dcache_pkg.sv` | Geometry, address decode, PLRU + word merge/select helpers |
| `rtl/dcache_if.sv` | CPU + backing memory interfaces |
| `rtl/dcache_tag_ram.sv` | valid / dirty / tag per way |
| `rtl/dcache_data_ram.sv` | Full 64 B lines |
| `rtl/dcache_plru.sv` | Per-set tree PLRU |
| `rtl/dcache_mshr.sv` | Single-entry MSHR + victim capture |
| `rtl/dcache_refill.sv` | 8-beat burst read/write FSM |
| `rtl/dcache_core.sv` | Hit/miss control + word datapath |
| `rtl/dcache_top.sv` | Top-level |
| `integration/dcache_tomasulo_wrap.sv` | Tomasulo port names + backing SRAM |
| `../Tomasulo3CPU/src/CPU_L1DCache.sv` | Integrated CPU + L1 D-cache subsystem |

---

## CPU + UVM Integration

The Tomasulo UVM top instantiates `CPU_L1DCache`, which contains:

- `CPU`
- `dcache_tomasulo_wrap`
- `dcache_top`
- `dcache_backing_mem`

The UVM environment preloads the backing memory while reset is asserted. The
D-cache monitor records accepted requests and completed responses. Its
scoreboard maintains an independent shadow memory and checks:

- every load response against the expected 64-bit word
- byte-strobe merging for accepted stores
- matching read and write responses
- no outstanding transactions when the test ends

The Spike scoreboard independently checks architectural CPU commits. Bare-metal
tests wait for the final `tohost` store response before ending, which allows a
write-allocate miss to finish cleanly.

### Setup

Compile the integrated UVM environment:

```bash
make uvm-compile USE_DW=1 UVM_TEST=cpu_baremetal_spike_test
```

Run one generated C-suite test:

```bash
python3 uvm/tools/run_baremetal_spike.py --sim-only memcpy
```

Run all generated C-suite tests:

```bash
python3 uvm/tools/run_baremetal_spike.py --sim-only all
```

Run all generated RISC-V architecture tests:

```bash
python3 uvm/tools/run_baremetal_spike.py --sim-only --arch-test all
```

Successful simulations report both:

```text
D-cache scoreboard passed: reads=... writes=...
Spike scoreboard matched ... commits for ...
```

See [`integration/README.md`](integration/README.md) for the detailed CPU/cache
handshake and standalone integration test.

---

## Coverage

Generate coverage for the C-suite and RISC-V architecture tests:

```bash
python3 uvm/tools/run_baremetal_spike.py --sim-only --coverage all
python3 uvm/tools/run_baremetal_spike.py --sim-only --arch-test --coverage all
```

Merge every saved VCS coverage database:

```bash
make uvm-cov-merge
```

The combined URG report is written to:

```text
/workspace/Tomasulo3CPU/build/uvm_cov_report/dashboard.html
```

Use `uvm-cov-merge`, not `uvm-cov-merge-baremetal`, when RISC-V test coverage
must be included.

---
