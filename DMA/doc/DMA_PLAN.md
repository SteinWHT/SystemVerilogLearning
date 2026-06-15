# DMA Engine — Industry-Level Implementation Plan

Standalone **AXI4 DMA controller** for the Tomasulo3CPU + AXISoC memory subsystem.

**Key decision:** RISC-V64 has **no DMA instructions**. Production SoCs expose DMA as an
**MMIO peripheral** (register slave) plus an **AXI master** (memory port). Software uses
only existing load/store and fence instructions — **no CPU decoder, CSR, or ROB changes**.

---

## What “Industry-Level” Means Here

Real DMA IP (ARM PL330, Xilinx AXI DMA, STM32 DMA, Synopsys DesignWare DMAC) typically
provides:

| Capability | This project | Notes |
|------------|--------------|-------|
| Memory-to-memory copy | Phase 1 | `MEMCPY` mode |
| Memset / constant fill | Phase 1 | `FILL` mode + `CH_FILL` register |
| Multiple channels | Phase 1 | 4 independent channels |
| AXI4 INCR bursts (64-bit) | Phase 1 | Match D$/SRAM width |
| Start / abort / status | Phase 1 | Per-channel `CTRL` / `STATUS` |
| Alignment + 4 KiB boundary checks | Phase 1 | Report error, don't hang |
| Scatter-gather (descriptor chains) | Phase 2 | `SG` mode + `dma_desc_t` in memory |
| 2D stride transfers | Phase 2 | `2D` mode for row-major tiles |
| Per-channel interrupts | Phase 2 | `IRQ_EN` / `IRQ_STATUS` (W1C) |
| Global soft reset | Phase 1 | Abort all channels |
| Cache / coherence policy | Phase 2 | See § Coherence below |

**Not in scope (later):** virtual addresses, IOMMU, security domains, PCIe-style
streaming ports, checksum/CRC.

---

## RISC-V Instructions Software Actually Uses

No new opcodes. Your CPU already supports everything needed:

| Instruction | Role in DMA driver |
|-------------|-------------------|
| **`SD` / `LD`** | Read/write 64-bit registers (`SRC`, `DST`, `LEN`, `DESC_PTR`, …) |
| **`SW` / `LW`** | Write/read 32-bit control and status (`CTRL`, `STATUS`, `IRQ_*`) |
| **`FENCE`** | Order CPU stores to **source buffer** before `START`; order **after `DONE`** before CPU reads destination |
| **`FENCE.I`** | Required if DMA wrote **instruction memory** (then I$ must see new code) |
| **`WFI`** (optional) | Block until PLIC/CLINT interrupt — only if you add an interrupt controller |

Example minimal driver (polling):

```c
#include "dma_regs.h"

static void dma_memcpy_phys(int ch, uint64_t dst, uint64_t src, uint64_t len) {
    dma_ch_src(ch)  = src;
    dma_ch_dst(ch)  = dst;
    dma_ch_len(ch)  = len;
    dma_ch_ctrl(ch) = DMA_CTRL_MODE_MEMCPY | dma_ch_ctrl(ch); // preserve IRQ_EN etc.
    __asm__ volatile("fence w,w" ::: "memory");  // publish src buffer to memory
    dma_ch_start(ch);
    while (dma_ch_busy(ch))
        ;
    __asm__ volatile("fence r,r" ::: "memory");  // observe DMA writes at dst
}
```

There is **nothing to add** to `riscv_types_pkg.sv` for DMA.

---

## Block Diagram

```text
                    ┌─────────────────────────────────────┐
  CPU LD/ST/SW ────►│  dma_regs (AXI-Lite slave)          │
  (MMIO window)     │    4 channels + global IRQ/reset    │
                    └──────────────┬──────────────────────┘
                                   │ dma_ch_if[0:3]
                    ┌──────────────▼──────────────────────┐
                    │  dma_engine                         │
                    │    channel arbiters + descriptor    │
                    │    fetch (SG mode)                  │
                    └──────────────┬──────────────────────┘
                                   │
                    ┌──────────────▼──────────────────────┐
                    │  dma_axi_master (AXI4 master)       │
                    └──────────────┬──────────────────────┘
                                   │
         D$ ──► cpu_axi ──┐        │
                         ├── axi_xbar_3x1 ──► axi_sram
         I$ ──► icache_axi┤        │
                         │        │
         DMA ──► dma_axi ─┘        │
```

The CPU reaches registers through a **system address map** entry (`0x0200_0000`).
That path is separate from the DMA **memory master** port.

---

## Register Map

Full constants in `DMA/rtl/dma_pkg.sv`.

### Global (`DMA_MMIO_BASE = 0x0200_0000`)

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| `0x000` | `VERSION` | RO | `0x0001_0000` |
| `0x004` | `CAPABILITIES` | RO | Feature bitmask + channel count |
| `0x008` | `GBL_CTRL` | WO | Bit 0: `SOFT_RESET` pulse |
| `0x00C` | `GBL_STATUS` | RO | Any-channel busy |
| `0x010` | `IRQ_EN` | RW | Per-channel interrupt enable |
| `0x014` | `IRQ_STATUS` | RW | W1C: done / error sticky flags |
| `0x018` | `IRQ_RAW` | RO | Combinational `irq_req` snapshot |

### Per-channel (`0x100 + ch * 0x80`, `ch ∈ [0..3]`)

| Offset | Name | Access | Description |
|--------|------|--------|-------------|
| `+0x00` | `SRC` | RW | Source physical byte address |
| `+0x08` | `DST` | RW | Destination physical byte address |
| `+0x10` | `LEN` | RW | Transfer length in bytes (`0` = illegal) |
| `+0x18` | `FILL` | RW | Constant value for `FILL` mode |
| `+0x20` | `CTRL` | RW | Mode, width, flags; **START/ABORT** are WO pulses |
| `+0x28` | `STATUS` | RO | `BUSY`, `DONE`, error flags + code |
| `+0x30` | `XFER_DONE` | RO | Bytes completed on last transfer |
| `+0x38` | `DESC_PTR` | RW | Physical address of first `dma_desc_t` (SG mode) |
| `+0x40` | `STRIDE` | RW | Row stride for `2D` mode |
| `+0x48` | `ROWS` | RW | Row count for `2D` mode |

### `CH_CTRL` bitfields

| Bits | Field | Meaning |
|------|-------|---------|
| 0 | `START` | Write 1 to launch (ignored if `BUSY`) |
| 1 | `ABORT` | Write 1 to cancel in-flight transfer |
| 2 | `IRQ_EN` | Pulse interrupt on `DONE` |
| 3 | `SRC_FIXED` | Don't increment source (device FIFO read) |
| 4 | `DST_FIXED` | Don't increment destination (device FIFO write) |
| 8:9 | `MODE` | `MEMCPY`, `FILL`, `SG`, `2D` |
| 12:13 | `WIDTH` | Beat width: 8 / 16 / 32 / 64 bits |

### Scatter-gather descriptor (in main memory)

```systemverilog
typedef struct packed {
    logic [63:0] src;
    logic [63:0] dst;
    logic [63:0] len;
    logic [31:0] ctrl;   // mode/width/flags
    logic [31:0] next;   // byte offset to next desc; 0 = end
} dma_desc_t;            // 32 bytes, 64-bit aligned
```

Software builds a linked list in RAM, sets `DESC_PTR`, selects `SG` mode, then `START`.
The engine fetches descriptors via its AXI master (same port as data movement).

---

## RTL Modules

| File | Role |
|------|------|
| `rtl/dma_pkg.sv` | Register map, modes, descriptor layout **(done)** |
| `rtl/dma_if.sv` | Per-channel internal interface **(done)** |
| `rtl/dma_regs.sv` | AXI-Lite slave, decode, W1C IRQ, pulse generation |
| `rtl/dma_channel.sv` | One channel FSM: MEMCPY / FILL / SG / 2D |
| `rtl/dma_axi_master.sv` | Shared AXI4 read/write engine (burst, 4KB check) |
| `rtl/dma_engine.sv` | Channel mux + descriptor fetch + arbitration |
| `rtl/dma_top.sv` | `axi_lite_if.slave` + `axi_if.master` |
| `integration/dma_soc_wrap.sv` | Hook into address map + `axi_xbar_3x1` |

Reference: `AXISoC/rtl/slave/axi_lite_sram.sv`, `L1DCache/integration/dcache_axi_master_bridge.sv`,
`AXISoC/tb/axi_burst_master_bfm.sv`.

---

## SoC Integration (no CPU RTL changes)

1. **`axi_xbar_3x1`** — add third master port for DMA (D$, I$, DMA).
2. **Address decode** — route `0x0200_0000` MMIO range to `dma_top` Lite slave.
   CPU already issues `LD`/`SD`; the D$ path must reach this slave (via a Lite
   crossbar or a dedicated decode stage on the memory fabric).
3. **`CPU_L1DCache_AXI`** — connect `dma_axi` master to fabric `m2`; leave CPU core untouched.

### Coherence with L1 D$

| Region | Policy |
|--------|--------|
| DMA MMIO registers | **Uncached** or bypass D$ (device memory) |
| Buffers in SRAM | **Non-cacheable** for DMA buffers *or* CPU **`FENCE` + flush** before/after (your D$ has `flush_req` for FENCE.I — document which approach you choose) |

Industry practice for bring-up: mark DMA buffer pages uncacheable in software link script;
add explicit flush/invalidate later if you add cacheable DMA.

---

## Verification Plan

| Level | Target | Checks |
|-------|--------|--------|
| Unit | `dma_axi_master_tb` | Single/multi-beat, `WSTRB`, 4KB, SLVERR recovery |
| Unit | `dma_regs_tb` | Decode, START pulse, W1C IRQ, soft reset |
| Unit | `dma_channel_tb` | MEMCPY, FILL, abort mid-transfer |
| Unit | `dma_sg_tb` | 3-descriptor chain, `next=0` termination |
| Integration | `dma_soc_tb` | Register programming + memory golden check |
| Contention | extend `dcache_axi_bridge_tb` pattern | CPU D$ + DMA concurrent |
| System | C driver + `memcpy` test | Scalar vs DMA compare |

---

## Implementation Order

1. ✅ MMIO register spec (`dma_pkg.sv`, `dma_if.sv`)
2. `dma_axi_master.sv` + TB
3. `dma_channel.sv` (MEMCPY + FILL only)
4. `dma_regs.sv` + Lite slave TB
5. `dma_engine.sv` + `dma_top.sv`
6. `axi_xbar_3x1` + address map + SoC integration
7. Scatter-gather + 2D modes
8. Interrupt wiring (needs SoC interrupt controller)
9. C header `dma_regs.h` + bare-metal benchmark vs scalar `memcpy`

---

## Why Not Custom Instructions?

| Approach | Verdict |
|----------|---------|
| Custom-0 `dma.start` / `dma.wait` | Non-standard; requires decoder, ROB, toolchain support |
| Machine CSRs (`0xBC0`…) | Non-standard; couples DMA to hart CSR file |
| **MMIO registers** | **Industry default**; zero CPU changes; portable driver code |

Custom instructions only help if you need **precise pipeline synchronization** beyond
what `FENCE` + MMIO ordering provide. For memory-to-memory DMA they are unnecessary.
