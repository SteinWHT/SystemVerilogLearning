# Tomasulo3CPU integration

The CPU
data-memory testbench drives `dcache_top` (+ backing SRAM) instead of the inline
1-cycle behavioural `dmem_array` read/write `always` blocks.

## Files

- `dcache_tomasulo_wrap.sv` — drop-in for the behavioural dmem. Presents the
  **memory side** of the CPU `dcache_*` interface, instantiates `dcache_top` + `dcache_backing_mem`, exposes a
  preload port (`mem_init_*`) and `stat_hits` / `stat_misses`.
- `dcache_axi_master_bridge.sv` — converts each cache backing-memory req/ack
  beat into a single-beat full AXI4 read or write transaction.
- `../../Tomasulo3CPU/src/CPU_L1DCache_AXI.sv` — CPU + D-cache + AXI bridge,
  connected as master 0 of the existing 2x1 AXI fabric. Master 1 is exposed
  as `dma_axi` for a future DMA master.

The current cache refill engine already sequences a line as eight single-word
req/ack transfers, so the bridge uses legal one-beat AXI4 transactions. A later
optimization can replace those with one eight-beat AXI burst without changing
the CPU-facing cache interface.

## AXI tests

```sh
cd AXISoC
make sim PROJECT=dcache_axi_bridge
```

The whole-system C-suite-style testbench is
`Tomasulo3CPU/tb/CPU_dcache_axi_tb.sv`.

## Handshake

| CPU port (dir)            | meaning                | cache (`dcache_top`)        |
|---------------------------|------------------------|-----------------------------|
| `dcache_rvalid` (out)     | load **request**       | `rvalid` (request in)       |
| `dcache_rready` (in)      | cache **ready**        | `rready` (ready out)        |
| `dcache_rresp_valid` (in) | read data valid        | `rresp_valid`               |
| `dcache_rresp_ready`(out) | LSB consumed data      | `rresp_ready`               |
| `dcache_wvalid` (out)     | store **request**      | `wvalid` (request in)       |
| `dcache_wready` (in)      | cache **ready**        | `wready` (ready out)        |
| `dcache_wresp_valid` (in) | write done             | `wresp_valid`               |
| `dcache_wresp_ready`(out) | SB drain               | `wresp_ready`               |

**Load-priority store handshake:** `dcache_core` has a single port
and prefers loads. The cache encodes this directly in its store handshake —
`wready = rready && !rvalid`.

## Write-back and the `tohost` poll

The cache is write-back, so a committed store to `tohost` sits in a dirty line
and may never reach the backing SRAM. Bare-metal testbenches read `tohost`
through a cache-aware backdoor (`peek_qword`): resident (possibly dirty) line
first, backing memory otherwise.
