// Full AXI4 SRAM slave: INCR and FIXED bursts, byte strobes, 4KB + range checks.

import axi_pkg::*;

module axi_sram #(
    parameter int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
    parameter int unsigned SRAM_DEPTH = 4096
) (
    input  logic clk,
    input  logic rst_n,
    axi_if.slave bus
);

    localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;

    logic [DATA_WIDTH-1:0] mem [SRAM_DEPTH];

    // ---- Write channel ----
    logic                  wr_busy;
    logic [7:0]            wr_beats_rem;
    logic [ADDR_WIDTH-1:0] wr_cur_addr;
    logic [2:0]            wr_size;
    logic [1:0]            wr_burst;
    axi_resp_e             wr_error;

    logic                  bvalid_r;
    logic [1:0]            bresp_r;

    // ---- Read channel ----
    logic                  rd_busy;
    logic [7:0]            rd_len_q;
    logic [7:0]            rd_beat_idx;
    logic [ADDR_WIDTH-1:0] rd_cur_addr;
    logic [2:0]            rd_size;
    logic [1:0]            rd_burst;
    axi_resp_e             rd_error_q;

    logic                  rvalid_r;
    logic [DATA_WIDTH-1:0] rdata_r;
    logic [1:0]            rresp_r;
    logic                  rlast_r;

    // One-cycle address-channel hold so ARLEN/ARLEN are stable before handshake.
    logic                  aw_hold;
    logic [7:0]            awlen_q;
    logic [ADDR_WIDTH-1:0] awaddr_q;
    logic [2:0]            awsize_q;
    logic [1:0]            awburst_q;

    logic                  ar_hold;
    logic [7:0]            arlen_q;
    logic [ADDR_WIDTH-1:0] araddr_q;
    logic [2:0]            arsize_q;
    logic [1:0]            arburst_q;

    assign bus.awready = !wr_busy && !(bvalid_r && !bus.bready) && aw_hold && bus.awvalid;
    assign bus.wready  = wr_busy && (wr_beats_rem != 8'd0);
    assign bus.bvalid  = bvalid_r;
    assign bus.bresp   = bresp_r;

    assign bus.arready = !rd_busy && ar_hold && bus.arvalid;
    assign bus.rvalid  = rvalid_r;
    assign bus.rdata   = rdata_r;
    assign bus.rresp   = rresp_r;
    assign bus.rlast   = rlast_r;

    function automatic int unsigned addr_idx(input logic [ADDR_WIDTH-1:0] addr);
        return addr_to_idx(addr, DATA_WIDTH);
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        axi_resp_e aw_check;

        if (!rst_n) begin
            wr_busy     <= 1'b0;
            wr_beats_rem <= 8'd0;
            bvalid_r    <= 1'b0;
            bresp_r     <= AXI_RESP_OKAY;
            rd_busy     <= 1'b0;
            rd_len_q    <= 8'd0;
            rd_beat_idx <= 8'd0;
            rd_error_q   <= AXI_RESP_OKAY;
            aw_hold     <= 1'b0;
            awlen_q     <= 8'd0;
            ar_hold     <= 1'b0;
            arlen_q     <= 8'd0;
            rvalid_r    <= 1'b0;
            rdata_r     <= '0;
            rresp_r     <= AXI_RESP_OKAY;
            rlast_r     <= 1'b0;
            for (int i = 0; i < SRAM_DEPTH; i++)
                mem[i] <= '0;
        end else begin
            if (bvalid_r && bus.bready)
                bvalid_r <= 1'b0;

            if (bus.awvalid && !wr_busy && !(bvalid_r && !bus.bready) && !aw_hold) begin
                aw_hold <= 1'b1;
            end else if (aw_hold && !bus.awvalid) begin
                aw_hold <= 1'b0;
            end else if (aw_hold && bus.awvalid && bus.awready) begin
                aw_hold      <= 1'b0;
                awlen_q      <= bus.awlen;
                awaddr_q     <= bus.awaddr[ADDR_WIDTH-1:0];
                awsize_q     <= bus.awsize;
                awburst_q    <= bus.awburst;
                aw_check     = check_burst(
                    bus.awaddr[ADDR_WIDTH-1:0],
                    bus.awlen,
                    bus.awsize,
                    bus.awburst,
                    DATA_WIDTH,
                    SRAM_DEPTH
                );
                wr_busy      <= 1'b1;
                wr_beats_rem <= bus.awlen + 8'd1;
                wr_cur_addr  <= bus.awaddr[ADDR_WIDTH-1:0];
                wr_size      <= bus.awsize;
                wr_burst     <= bus.awburst;
                wr_error     <= aw_check;
            end

            // Accept write data beats
            if (bus.wvalid && bus.wready) begin
                if (wr_error == AXI_RESP_OKAY) begin
                    int unsigned widx;
                    widx = addr_idx(wr_cur_addr);
                    for (int i = 0; i < STRB_WIDTH; i++) begin
                        if (bus.wstrb[i])
                            mem[widx][8*i +: 8] <= bus.wdata[8*i +: 8];
                    end
                end

                if (wr_beats_rem == 8'd1 && !bus.wlast && (wr_error == AXI_RESP_OKAY))
                    wr_error <= AXI_RESP_SLVERR;

                wr_cur_addr  <= burst_next_addr(wr_cur_addr, wr_size, wr_burst);
                wr_beats_rem <= wr_beats_rem - 8'd1;

                if (wr_beats_rem == 8'd1) begin
                    wr_busy  <= 1'b0;
                    bresp_r  <= wr_error;
                    bvalid_r <= 1'b1;
                end
            end

            if (bus.arvalid && !rd_busy && !ar_hold) begin
                ar_hold <= 1'b1;
            end else if (ar_hold && !bus.arvalid) begin
                ar_hold <= 1'b0;
            end else if (ar_hold && bus.arvalid && bus.arready) begin
                ar_hold    <= 1'b0;
                arlen_q    <= bus.arlen;
                araddr_q   <= bus.araddr[ADDR_WIDTH-1:0];
                arsize_q   <= bus.arsize;
                arburst_q  <= bus.arburst;
                rd_len_q   <= bus.arlen;
                rd_error_q <= check_burst(
                    bus.araddr[ADDR_WIDTH-1:0],
                    bus.arlen,
                    bus.arsize,
                    bus.arburst,
                    DATA_WIDTH,
                    SRAM_DEPTH
                );
                rd_busy     <= 1'b1;
                rd_beat_idx <= 8'd0;
                rd_cur_addr <= bus.araddr[ADDR_WIDTH-1:0];
                rd_size     <= bus.arsize;
                rd_burst    <= bus.arburst;
            end

            // Read data: one beat at a time; advance index after each R handshake.
            if (rd_busy) begin
                if (rvalid_r && bus.rready) begin
                    rvalid_r <= 1'b0;
                    if (rd_beat_idx == rd_len_q) begin
                        rd_busy <= 1'b0;
                    end else begin
                        rd_beat_idx  <= rd_beat_idx + 8'd1;
                        rd_cur_addr  <= burst_next_addr(rd_cur_addr, rd_size, rd_burst);
                    end
                end else if (!rvalid_r) begin
                    if (rd_error_q == AXI_RESP_OKAY)
                        rdata_r <= mem[addr_idx(rd_cur_addr)];
                    else
                        rdata_r <= '0;
                    rresp_r  <= rd_error_q;
                    rlast_r  <= (rd_beat_idx == rd_len_q);
                    rvalid_r <= 1'b1;
                end
            end
        end
    end

endmodule
