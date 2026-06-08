// Bind-on assertions for icache_top (simulation only).

module icache_assertions import icache_pkg::*; (
    input logic                clk,
    input logic                rst_n,
    input logic                resp_valid,
    input logic                resp_ready,
    input fetch_data_t         resp_data,
    input logic                mem_req,
    input logic                mem_we,
    input logic                mem_ack
);

    property p_resp_hold;
        @(posedge clk) disable iff (!rst_n)
        (resp_valid && !resp_ready) |=> resp_valid;
    endproperty
    a_resp_hold: assert property (p_resp_hold);

    property p_rdata_stable;
        @(posedge clk) disable iff (!rst_n)
        (resp_valid && !resp_ready) |=> $stable(resp_data);
    endproperty
    a_rdata_stable: assert property (p_rdata_stable);

    property p_mem_ack;
        @(posedge clk) disable iff (!rst_n)
        mem_req |-> ##[1:8] mem_ack;
    endproperty
    a_mem_ack: assert property (p_mem_ack);

    property p_read_only;
        @(posedge clk) disable iff (!rst_n)
        mem_we == 1'b0;
    endproperty
    a_read_only: assert property (p_read_only);

endmodule

bind icache_top icache_assertions u_icache_assertions (
    .clk        (clk),
    .rst_n      (rst_n),
    .resp_valid (resp_valid),
    .resp_ready (resp_ready),
    .resp_data  (resp_data),
    .mem_req    (mem_req),
    .mem_we     (mem_we),
    .mem_ack    (mem_ack)
);
