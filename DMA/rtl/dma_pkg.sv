`ifndef DMA_PKG_SV
`define DMA_PKG_SV

// Register map and constants for an AXI DMA controller (MMIO slave + AXI master).
//
// Industry DMA blocks (ARM PL330, Xilinx AXI DMA, STM32 DMA, Synopsys DW_axi_dmac)
// are controlled through memory-mapped registers, not ISA opcodes. Software on
// this CPU uses existing RV64I load/store instructions only.
//
// See DMA/doc/DMA_PLAN.md for the full feature breakdown and bring-up order.
package dma_pkg;

    import axi_pkg::*;

    // ---------------------------------------------------------------
    // SoC placement
    // ---------------------------------------------------------------
    localparam int unsigned DMA_MMIO_BASE       = 32'h0200_0000;
    localparam int unsigned DMA_MMIO_SIZE_BYTES = 32'h0000_1000; // 4 KiB aperture

    localparam int unsigned DMA_NUM_CHANNELS = 4;
    localparam int unsigned DMA_CH_STRIDE      = 32'h80; // bytes between channel bases

    // ---------------------------------------------------------------
    // Global register offsets (from DMA_MMIO_BASE)
    // ---------------------------------------------------------------
    localparam int unsigned REG_VERSION      = 32'h000;
    localparam int unsigned REG_CAPABILITIES = 32'h004;
    localparam int unsigned REG_GBL_CTRL     = 32'h008;
    localparam int unsigned REG_GBL_STATUS   = 32'h00C;
    localparam int unsigned REG_IRQ_EN       = 32'h010;
    localparam int unsigned REG_IRQ_STATUS   = 32'h014; // W1C
    localparam int unsigned REG_IRQ_RAW      = 32'h018;

    localparam int unsigned REG_CH_BASE      = 32'h100;

    // ---------------------------------------------------------------
    // Per-channel register offsets (from channel base)
    // ---------------------------------------------------------------
    localparam int unsigned CH_REG_SRC       = 32'h00;
    localparam int unsigned CH_REG_DST       = 32'h08;
    localparam int unsigned CH_REG_LEN       = 32'h10; // byte count; 0 = no transfer
    localparam int unsigned CH_REG_FILL      = 32'h18; // memset / constant write value
    localparam int unsigned CH_REG_CTRL      = 32'h20;
    localparam int unsigned CH_REG_STATUS    = 32'h28;
    localparam int unsigned CH_REG_XFER_DONE = 32'h30; // bytes completed (RO)
    localparam int unsigned CH_REG_DESC_PTR  = 32'h38; // scatter-gather list head
    localparam int unsigned CH_REG_STRIDE    = 32'h40; // 2D: row stride bytes
    localparam int unsigned CH_REG_ROWS      = 32'h48; // 2D: row count (1 = 1D)

    // ---------------------------------------------------------------
    // REG_VERSION / REG_CAPABILITIES
    // ---------------------------------------------------------------
    localparam logic [31:0] DMA_VERSION = 32'h0001_0000; // 1.0

    localparam int unsigned CAP_FLAG_SG       = 0; // scatter-gather descriptors
    localparam int unsigned CAP_FLAG_2D       = 1; // stride + rows
    localparam int unsigned CAP_FLAG_FILL     = 2; // memset mode
    localparam int unsigned CAP_FLAG_PER_CH_IRQ = 3;

    // ---------------------------------------------------------------
    // REG_GBL_CTRL
    // ---------------------------------------------------------------
    localparam int unsigned GBL_CTRL_SOFT_RESET_BIT = 0; // WO pulse: abort all, clear state

    // ---------------------------------------------------------------
    // CH_REG_CTRL
    // ---------------------------------------------------------------
    localparam int unsigned CH_CTRL_START_BIT     = 0; // WO pulse
    localparam int unsigned CH_CTRL_ABORT_BIT     = 1; // WO pulse
    localparam int unsigned CH_CTRL_IRQ_EN_BIT    = 2; // interrupt when channel done
    localparam int unsigned CH_CTRL_SRC_FIXED_BIT = 3; // src address does not increment
    localparam int unsigned CH_CTRL_DST_FIXED_BIT = 4; // dst address does not increment

    localparam int unsigned CH_CTRL_MODE_LSB = 8;
    localparam int unsigned CH_CTRL_MODE_MSB = 9;
    localparam int unsigned CH_CTRL_WIDTH_LSB = 12;
    localparam int unsigned CH_CTRL_WIDTH_MSB = 13;

    typedef enum logic [1:0] {
        DMA_MODE_MEMCPY = 2'b00, // src -> dst for LEN bytes
        DMA_MODE_FILL   = 2'b01, // FILL -> dst for LEN bytes
        DMA_MODE_SG     = 2'b10, // walk descriptor list at DESC_PTR
        DMA_MODE_2D     = 2'b11  // 2D tile: STRIDE x ROWS per row segment
    } dma_mode_e;

    typedef enum logic [1:0] {
        DMA_WIDTH_8  = 2'b00,
        DMA_WIDTH_16 = 2'b01,
        DMA_WIDTH_32 = 2'b10,
        DMA_WIDTH_64 = 2'b11
    } dma_width_e;

    // ---------------------------------------------------------------
    // CH_REG_STATUS
    // ---------------------------------------------------------------
    localparam int unsigned CH_STAT_BUSY_BIT      = 0;
    localparam int unsigned CH_STAT_DONE_BIT      = 1; // sticky until START or SW clear
    localparam int unsigned CH_STAT_ERR_BIT       = 2; // AXI SLVERR/DECERR or bad prog
    localparam int unsigned CH_STAT_ALIGN_ERR_BIT = 3;
    localparam int unsigned CH_STAT_4KB_ERR_BIT   = 4; // burst crossed 4 KiB boundary

    localparam int unsigned CH_STAT_ERR_CODE_LSB = 8;
    localparam int unsigned CH_STAT_ERR_CODE_MSB = 11;

    typedef enum logic [3:0] {
        DMA_ERR_NONE     = 4'h0,
        DMA_ERR_AXI_SLV  = 4'h1,
        DMA_ERR_AXI_DEC  = 4'h2,
        DMA_ERR_ALIGN    = 4'h3,
        DMA_ERR_4KB      = 4'h4,
        DMA_ERR_BAD_DESC = 4'h5,
        DMA_ERR_BUSY     = 4'h6  // START while channel still busy
    } dma_err_e;

    // ---------------------------------------------------------------
    // Scatter-gather descriptor (64-bit aligned, in main memory)
    // Same layout as many embedded DMACs (PL330 / DW_axi_dmac style).
    // ---------------------------------------------------------------
    localparam int unsigned DESC_SIZE_BYTES = 32;

    typedef struct packed {
        logic [63:0] src;
        logic [63:0] dst;
        logic [63:0] len;
        logic [31:0] ctrl;   // mode/width/flags (same encoding as CH_REG_CTRL[15:0])
        logic [31:0] next;   // byte offset of next descriptor; 0 = end of chain
    } dma_desc_t;

    // ---------------------------------------------------------------
    // AXI master defaults
    // ---------------------------------------------------------------
    localparam logic [2:0] DMA_AXI_SIZE  = 3'd3; // 8 bytes per beat
    localparam logic [1:0] DMA_AXI_BURST = axi_pkg::AXI_BURST_INCR;
    localparam logic [3:0] DMA_AXI_ID    = 4'd2; // distinct from D$ (0) and I$ (1)

    // ---------------------------------------------------------------
    // Address decode helpers
    // ---------------------------------------------------------------
    function automatic bit in_mmio_window(input logic [31:0] byte_addr);
        return (byte_addr >= DMA_MMIO_BASE) &&
               (byte_addr <  (DMA_MMIO_BASE + DMA_MMIO_SIZE_BYTES));
    endfunction

    function automatic int unsigned channel_index(input logic [31:0] byte_offset);
        if (byte_offset < REG_CH_BASE)
            return -1;
        return int'((byte_offset - REG_CH_BASE) / DMA_CH_STRIDE);
    endfunction

endpackage

`endif
