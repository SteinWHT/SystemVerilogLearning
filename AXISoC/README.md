# AXISoC

AXISoC is the shared memory subsystem I built to connect my Tomasulo CPU and
L1 D-cache to an AXI4 memory fabric. The project began as an AXI4-Lite
prototype, then grew into a full AXI4 implementation with burst support,
two-master arbitration, an SRAM controller, protocol assertions, and a bridge
for the cache's existing backing-memory interface.

The resulting system is used by `Tomasulo3CPU` as this memory path:

```text
Tomasulo CPU
     |
     v
L1 D-cache
     |
     v
D-cache to AXI4 bridge ----+
                           |
                           v
                    2x1 AXI4 fabric ----> AXI SRAM
                           ^
                           |
                    DMA master port
```

The second master port is tied idle in the current CPU testbench, but it is a
real AXI4 port and has been verified with a DMA-style BFM under contention.

## What I Implemented

### Parameterized AXI4 interface and package

I defined a reusable SystemVerilog interface with master, slave, and monitor
modports. The shared package contains response and burst encodings plus helper
functions for:

- Burst address generation
- Transfer-size alignment
- Legal WRAP burst lengths
- 4 KB boundary checks
- SRAM range checks
- `SLVERR` and `DECERR` response generation

The default configuration is a 32-bit byte address, 64-bit data bus, and
4-bit transaction ID.

### AXI4 SRAM controller

`rtl/slave/axi_sram.sv` implements a synthesizable-style memory controller
with independent read and write state.

Implemented behavior:

- Single-beat and multi-beat transfers
- `FIXED`, `INCR`, and legal `WRAP` bursts
- Burst lengths from 1 to 256 beats
- AXI ID propagation on B and R responses
- Narrow, aligned transfers on the 64-bit bus
- Byte writes through `WSTRB`
- Stable B and R payloads while backpressured
- `WLAST` validation and malformed-burst recovery
- `SLVERR` for invalid size, alignment, burst, or 4 KB crossing
- `DECERR` for addresses outside the SRAM range
- A synchronous initialization port used to load C-program data images

### Two-master interconnect

`rtl/interconnect/axi_xbar_2x1.sv` allows two AXI masters to share one SRAM
slave. I chose a serialized, single-transaction fabric because the current
cache bridge only generates one outstanding request and the future DMA port
does not yet require high throughput.

The fabric:

- Arbitrates complete read or write transactions
- Locks ownership through the final B or R handshake
- Routes responses only to the selected master
- Preserves transaction IDs
- Uses round-robin arbitration between masters
- Alternates read/write preference when one master presents AW and AR together

This design favors simple ownership tracking and predictable behavior over
multiple outstanding or reordered transactions.

### D-cache to AXI4 bridge

The L1 D-cache already used a word-indexed `req/ack` backing-memory port.
Rather than redesigning the cache, I added
`../L1DCache/integration/dcache_axi_master_bridge.sv`.

Each cache request becomes one 64-bit AXI4 transaction:

- Cache refill read -> single-beat AR/R transaction
- Dirty eviction write -> single-beat AW/W/B transaction
- Cache word index -> AXI byte address
- AXI response or ID error -> sticky bridge error flag

The bridge lets the cache use the full AXI fabric while keeping its internal
refill and eviction interface unchanged.

### CPU integration

`../Tomasulo3CPU/src/CPU_L1DCache_AXI.sv` combines:

- Tomasulo CPU
- L1 D-cache
- D-cache AXI bridge
- Two-master AXI interconnect
- AXI SRAM
- External DMA master port

`../Tomasulo3CPU/tb/CPU_dcache_axi_tb.sv` loads bare-metal instruction and
data images, runs the complete hierarchy, observes the cache-aware `tohost`
location, and reports cache hits, misses, and AXI errors.

The C-suite runner uses this AXI system by default:

```bash
cd ../Tomasulo3CPU/cprogram/c_suite
python3 run_suite_dcache.py
```

The original CPU plus D-cache backing-memory system remains available for
comparison:

```bash
python3 run_suite_dcache.py --system dcache
```

## Verification

I used layered directed verification so each block was checked before CPU
integration:

| Testbench | Scope | Current result |
|-----------|-------|----------------|
| `tb/axi_sram_tb.sv` | SRAM bursts, errors, strobes, IDs, backpressure, initialization | 25/25 pass |
| `tb/axi_sys_tb.sv` | Two-master arbitration, routing, fairness, data integrity | 5/5 pass |
| `tb/dcache_axi_bridge_tb.sv` | Cache bridge plus concurrent DMA-style traffic | 7/7 pass |
| `Tomasulo3CPU/tb/CPU_dcache_axi_tb.sv` | CPU, cache, bridge, fabric, and SRAM | C-suite sign-off in progress |

`sva/axi_assertions.sv` checks:

- VALID and payload stability while stalled
- W beats only after an accepted AW
- B response only after all write beats
- BID and RID matching the accepted request ID
- WLAST and RLAST agreement with burst length
- No second outstanding read or write on the monitored interface

See [doc/VERIFICATION_PLAN.md](doc/VERIFICATION_PLAN.md) for the feature
matrix, pass criteria, and remaining work.

## Running The Tests

From `AXISoC`:

```bash
make sim PROJECT=axi_sram
make sim PROJECT=axi_sys
make sim PROJECT=dcache_axi_bridge
```

The Makefile selects Questa, VCS, Verilator, or Icarus Verilog based on the
tools available. Questa or VCS is preferred; the current directed full-AXI
regression also passes with Verilator.

To run one CPU program through the complete AXI hierarchy:

```bash
cd ../Tomasulo3CPU
make sim PROJECT=CPU_dcache_axi \
  PLUSARGS="+IMEM_FILE=$(pwd)/cprogram/c_suite/build/recursion/imem.hex \
  +DMEM_FILE=$(pwd)/cprogram/c_suite/build/recursion/dmem.hex \
  +TOHOST_ADDR=1008 +TEST_NAME=recursion +MAX_CYCLES=5000000"
```

## Repository Layout

```text
AXISoC/
|-- rtl/
|   |-- pkg/                 AXI constants and burst helpers
|   |-- intf/                AXI4 and legacy AXI4-Lite interfaces
|   |-- slave/               AXI SRAM controllers
|   |-- interconnect/        Two-master fabrics
|   `-- top/                 Interconnect plus SRAM wrappers
|-- sva/                     Protocol assertions
|-- tb/                      BFMs and directed testbenches
|-- doc/VERIFICATION_PLAN.md Verification scope and status
`-- Makefile                 Multi-simulator regression flow
```

The AXI4-Lite files record the first version of the design. The maintained and
actively verified path is the full AXI4 implementation used by the cache and
CPU integration.

## Current Boundaries

This is a bounded AXI4 implementation, not a general-purpose high-performance
crossbar:

- The interconnect permits one complete transaction at a time.
- Transactions are not reordered.
- The cache bridge emits only single-beat, full-width transfers.
- Exclusive accesses, atomic operations, and multiple slaves are not present.
- Clock-domain crossing is outside the current scope.
- The DMA port is verified with a BFM but no DMA RTL master is connected yet.

These boundaries are deliberate. They provide a complete and verifiable CPU
memory path while leaving clear extension points for a DMA engine, multiple
outstanding transactions, address decoding, and additional slaves.
