# L1ICache — L1 Instruction Cache

Standalone **L1 I-cache**: RTL and directed testbenches, mirroring the [L1DCache](../L1DCache/) organization for later AXI4 and Tomasulo3CPU integration.

---

## Status

| Item | State |
|------|--------|
| RTL | **Complete** — core, MSHR, burst refill, PLRU, tag/data RAM |
| Module tests | `icache_plru_tb`, `icache_core_tb` |
| CPU hookup | Fetch port aligned with Tomasulo3CPU IFQ (`req_*` / `resp_*`) |
| AXI bridge | Planned (reuse L1DCache-style single-beat bridge on 64-bit bus) |

### Features

- 16 KiB, 4-way set-associative, **64-byte lines**, read-only  
- 32-bit instruction fetch (RISC-V default; one instruction per request)  
- Tree PLRU replacement, lowest-invalid-way allocation, single MSHR  
- **8-beat burst** line refill over a 64-bit memory bus (same backing model as L1DCache)  
- Valid/ready fetch port (`icache_if` / `icache_top`)  
- `inv_all` port for fence.i-style full invalidation  
- Hit/miss statistics on `icache_top`  
- All geometry derived from `icache_pkg.sv`

---

## Simulate

```bash
cd L1ICache
make sim PROJECT=icache_plru    # PLRU golden check
make sim PROJECT=icache_core    # full cache directed tests
```

For SVA bind checks:

```bash
make sim PROJECT=icache_core USE_SVA=1
```

---

## RTL map

| File | Role |
|------|------|
| `rtl/icache_pkg.sv` | Geometry, address decode, PLRU + instruction select helpers |
| `rtl/icache_if.sv` | CPU fetch + backing memory interfaces |
| `rtl/icache_tag_ram.sv` | valid / tag per way |
| `rtl/icache_data_ram.sv` | Full 64 B lines |
| `rtl/icache_plru.sv` | Per-set tree PLRU |
| `rtl/icache_mshr.sv` | Single-entry MSHR |
| `rtl/icache_refill.sv` | 8-beat line read engine |
| `rtl/icache_core.sv` | Hit/miss FSM |
| `rtl/icache_top.sv` | Top wrapper + statistics |

---

## CPU interface (IFQ-compatible)

```
req_valid / req_ready / req_addr   — fetch request (byte PC)
resp_valid / resp_ready / resp_data — 32-bit instruction response
inv_all                             — invalidate entire cache (fence.i)
```

Map to Tomasulo3CPU IFQ as:

- `imem_req_valid`  ↔ `req_valid`
- `imem_addr`       ↔ `req_addr`
- `imem_resp_*`     ↔ `resp_*`

Wider fetch (`IMEM_WIDTH` > 32) can be added by extending `FETCH_WIDTH` in `icache_pkg.sv`.

---

## Memory bus

Same 64-bit req/ack port as L1DCache (`mem_req`, `mem_idx`, `mem_rdata`, `mem_ack`).  
`mem_we` is always 0 (read-only). An AXI master bridge can be copied from `L1DCache/integration/dcache_axi_master_bridge.sv` with read-only restrictions.
