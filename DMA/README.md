# DMA — AXI DMA Controller for Tomasulo3CPU

Industry-style **AXI4 DMA controller**: AXI-Lite **register slave** (software control) +
AXI4 **memory master** (data movement). Targets shared AXISoC SRAM alongside L1 D-cache
and L1 I-cache.

**No new RISC-V instructions.** Software uses existing `LD`/`SD`/`SW`/`LW` and `FENCE`.

---

## Status

| Item | State |
|------|--------|
| Plan | [`doc/DMA_PLAN.md`](doc/DMA_PLAN.md) |
| Register spec | **Done** — `rtl/dma_pkg.sv` |
| RTL | **Not started** |
| SoC hookup | **Not started** — 3-master fabric + MMIO decode |
| CPU changes | **None required** |

---

## Software Interface (summary)

MMIO base: **`0x0200_0000`** (4 KiB), **4 channels**.

| What software does | How |
|--------------------|-----|
| Set addresses / length | `SD` to channel `SRC`, `DST`, `LEN` |
| Start transfer | `SW` START bit in channel `CTRL` |
| Poll completion | `LW` channel `STATUS` until `BUSY` clear |
| Memset | Program `FILL`, select `FILL` mode, `START` |
| Scatter-gather | Build `dma_desc_t` list in RAM, set `DESC_PTR`, `SG` mode |
| Ordering | `FENCE` before start and after done |

Full register map: [`rtl/dma_pkg.sv`](rtl/dma_pkg.sv) and [`doc/DMA_PLAN.md`](doc/DMA_PLAN.md).

---

## Folder Layout

```text
DMA/
├── README.md
├── doc/DMA_PLAN.md
├── rtl/
│   ├── dma_pkg.sv          # MMIO map, modes, descriptor layout
│   ├── dma_if.sv           # internal per-channel interface
│   ├── dma_regs.sv             (TODO) AXI-Lite slave
│   ├── dma_channel.sv          (TODO) channel FSM
│   ├── dma_axi_master.sv       (TODO) shared AXI master
│   ├── dma_engine.sv           (TODO)
│   └── dma_top.sv              (TODO)
├── integration/
│   └── dma_soc_wrap.sv         (TODO)
├── sw/
│   └── dma_regs.h              (TODO) C header
└── tb/
    └── ...                     (TODO)
```

---

## Related Code

- AXI fabric: [`AXISoC/`](../AXISoC/)
- AXI-Lite reference: [`AXISoC/rtl/slave/axi_lite_sram.sv`](../AXISoC/rtl/slave/axi_lite_sram.sv)
- CPU top (idle DMA master port): [`Tomasulo3CPU/src/CPU_L1DCache_AXI.sv`](../Tomasulo3CPU/src/CPU_L1DCache_AXI.sv)
- Contention TB: [`AXISoC/tb/dcache_axi_bridge_tb.sv`](../AXISoC/tb/dcache_axi_bridge_tb.sv)
