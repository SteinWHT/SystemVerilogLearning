# Tomasulo3CPU integration

The CPU
data-memory testbench drives `dcache_top` (+ backing SRAM) instead of the inline
1-cycle behavioural `dmem_array` read/write `always` blocks. The CPU core RTL
under `Tomasulo3CPU/src/` is unchanged (Track A).

## Files

- `dcache_tomasulo_wrap.sv` — drop-in for the behavioural dmem. Presents the
  **memory side** of the CPU `dcache_*` interface (so CPU ⇄ wrapper connect 1:1
  by name), instantiates `dcache_top` + `dcache_backing_mem`, exposes a
  preload port (`mem_init_*`) and `stat_hits` / `stat_misses`.

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
