`ifndef DMA_IF_SV
`define DMA_IF_SV

// Internal channel programming view (between MMIO reg block and channel FSM).
//
// Software never drives this interface directly. The CPU programs the engine
// with normal LD/SD/SW to the AXI-Lite register slave; dma_regs.sv converts
// those writes into channel state consumed by dma_engine.sv.
interface dma_ch_if (
    input logic clk,
    input logic rst_n
);
    import dma_pkg::*;

    // Programmed by MMIO writes (held until next START or SOFT_RESET).
    logic [63:0] src;
    logic [63:0] dst;
    logic [63:0] len;
    logic [63:0] fill;
    logic [63:0] desc_ptr;
    logic [63:0] stride;
    logic [31:0] rows;
    dma_mode_e   mode;
    dma_width_e  width;
    logic        src_fixed;
    logic        dst_fixed;
    logic        irq_en;

    // Pulses from register block
    logic        start_pulse;
    logic        abort_pulse;

    // Status back to register block
    logic        busy;
    logic        done;
    logic        err;
    dma_err_e    err_code;
    logic [63:0] bytes_done;

    // Level to global interrupt aggregator
    logic        irq_req;

    modport engine (
        input  clk,
        input  rst_n,
        input  src,
        input  dst,
        input  len,
        input  fill,
        input  desc_ptr,
        input  stride,
        input  rows,
        input  mode,
        input  width,
        input  src_fixed,
        input  dst_fixed,
        input  irq_en,
        input  start_pulse,
        input  abort_pulse,
        output busy,
        output done,
        output err,
        output err_code,
        output bytes_done,
        output irq_req
    );

    modport regs (
        input  clk,
        input  rst_n,
        output src,
        output dst,
        output len,
        output fill,
        output desc_ptr,
        output stride,
        output rows,
        output mode,
        output width,
        output src_fixed,
        output dst_fixed,
        output irq_en,
        output start_pulse,
        output abort_pulse,
        input  busy,
        input  done,
        input  err,
        input  err_code,
        input  bytes_done,
        input  irq_req
    );

endinterface

`endif
