// Bind-on assertions for dcache_top (simulation only; Questa/VCS).
// Checks the response-channel contract and memory-bus sanity.

module dcache_assertions import dcache_pkg::*; (
    input logic                clk,
    input logic                rst_n,
    input logic                rresp_valid,
    input logic                rresp_ready,
    input cache_word_t         rdata,
    input logic                wresp_valid,
    input logic                wresp_ready,
    input logic                mem_req,
    input logic                mem_we,
    input logic                mem_ack
);

    // A held read response must not drop and its data must be stable until consumed.
    property p_rresp_hold;
        @(posedge clk) disable iff (!rst_n)
        (rresp_valid && !rresp_ready) |=> rresp_valid;
    endproperty
    a_rresp_hold: assert property (p_rresp_hold);

    property p_rdata_stable;
        @(posedge clk) disable iff (!rst_n)
        (rresp_valid && !rresp_ready) |=> $stable(rdata);
    endproperty
    a_rdata_stable: assert property (p_rdata_stable);

    // A held write response must not drop until consumed.
    property p_wresp_hold;
        @(posedge clk) disable iff (!rst_n)
        (wresp_valid && !wresp_ready) |=> wresp_valid;
    endproperty
    a_wresp_hold: assert property (p_wresp_hold);

    // Every memory request is acknowledged within a bounded window (1-cycle SRAM
    // model uses 1; allow slack for slower backings).
    property p_mem_ack;
        @(posedge clk) disable iff (!rst_n)
        mem_req |-> ##[1:8] mem_ack;
    endproperty
    a_mem_ack: assert property (p_mem_ack);

    // Read and write responses are never asserted in the same cycle (one port
    // served at a time in this blocking design).
    property p_resp_excl;
        @(posedge clk) disable iff (!rst_n)
        !(rresp_valid && wresp_valid);
    endproperty
    a_resp_excl: assert property (p_resp_excl);

endmodule

bind dcache_top dcache_assertions u_dcache_sva (
    .clk         (clk),
    .rst_n       (rst_n),
    .rresp_valid (rresp_valid),
    .rresp_ready (rresp_ready),
    .rdata       (rdata),
    .wresp_valid (wresp_valid),
    .wresp_ready (wresp_ready),
    .mem_req     (mem_req),
    .mem_we      (mem_we),
    .mem_ack     (mem_ack)
);
