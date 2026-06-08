// L1 I-cache top: CPU fetch port + 64-bit read-only memory bus + statistics.

module icache_top #(
    parameter int unsigned FETCH_INSTR_NUM = 1
) (
    input  logic                            clk,
    input  logic                            rst_n,

    // CPU fetch port (IFQ-compatible naming)
    input  logic                            req_valid,
    output logic                            req_ready,
    input  icache_pkg::cache_addr_t         req_addr,
    output logic                            resp_valid,
    input  logic                            resp_ready,
    output logic [FETCH_INSTR_NUM*32-1:0]   resp_data,
    output logic [FETCH_INSTR_NUM-1:0]      resp_valid_mask,

    // Full invalidation (fence.i hook)
    input  logic                            inv_all,

    // 64-bit memory bus (read-only; mem_we always 0)
    output logic                            mem_req,
    output logic                            mem_we,
    output icache_pkg::mem_idx_t            mem_idx,
    output icache_pkg::mem_word_t           mem_wdata,
    input  icache_pkg::mem_word_t           mem_rdata,
    input  logic                            mem_ack,

    output logic [31:0]                     stat_hits,
    output logic [31:0]                     stat_misses
);

    icache_core #(
        .FETCH_INSTR_NUM(FETCH_INSTR_NUM)
    ) u_core (
        .clk         (clk),
        .rst_n       (rst_n),
        .req_valid   (req_valid),
        .req_ready   (req_ready),
        .req_addr    (req_addr),
        .resp_valid  (resp_valid),
        .resp_ready  (resp_ready),
        .resp_data   (resp_data),
        .resp_valid_mask (resp_valid_mask),
        .inv_all     (inv_all),
        .mem_req     (mem_req),
        .mem_we      (mem_we),
        .mem_idx     (mem_idx),
        .mem_wdata   (mem_wdata),
        .mem_rdata   (mem_rdata),
        .mem_ack     (mem_ack),
        .stat_hits   (stat_hits),
        .stat_misses (stat_misses)
    );

endmodule
