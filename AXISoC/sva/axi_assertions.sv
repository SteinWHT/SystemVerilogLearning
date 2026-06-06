module axi_assertions #(
    parameter int unsigned ADDR_WIDTH  = axi_pkg::AXI_ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH  = axi_pkg::AXI_DATA_WIDTH,
    parameter int unsigned ID_WIDTH    = axi_pkg::AXI_ID_WIDTH,
    parameter bit          CHECK_WLAST = 1'b1
) (
    input logic clk,
    input logic rst_n,
    axi_if.monitor bus
);

    localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;

    logic awvalid_q;
    logic awready_q;
    logic wvalid_q;
    logic wready_q;
    logic wlast_q;
    logic bvalid_q;
    logic bready_q;
    logic arvalid_q;
    logic arready_q;
    logic rvalid_q;
    logic rready_q;
    logic rlast_q;
    logic [7:0]          awlen_q;
    logic [7:0]          arlen_q;
    logic [ID_WIDTH-1:0] awid_q;
    logic [ID_WIDTH-1:0] bid_q;
    logic [ID_WIDTH-1:0] arid_q;
    logic [ID_WIDTH-1:0] rid_q;
    logic [ID_WIDTH+ADDR_WIDTH+28:0] aw_payload_q;
    logic [DATA_WIDTH+STRB_WIDTH:0]  w_payload_q;
    logic [ID_WIDTH+1:0]             b_payload_q;
    logic [ID_WIDTH+ADDR_WIDTH+28:0] ar_payload_q;
    logic [ID_WIDTH+DATA_WIDTH+2:0]  r_payload_q;

    logic                  write_open;
    logic                  write_data_done;
    logic                  b_response_seen;
    logic [8:0]            write_beats_rem;
    logic [ID_WIDTH-1:0]   write_id;
    logic                  read_open;
    logic [8:0]            read_beats_rem;
    logic [ID_WIDTH-1:0]   read_id;

    // Sample on the falling edge so all checks describe the next rising-edge
    // transfer and do not race combinational READY changes after a handshake.
    always_ff @(negedge clk or negedge rst_n) begin
        if (!rst_n) begin
            awvalid_q       <= 1'b0;
            awready_q       <= 1'b0;
            wvalid_q        <= 1'b0;
            wready_q        <= 1'b0;
            wlast_q         <= 1'b0;
            bvalid_q        <= 1'b0;
            bready_q        <= 1'b0;
            arvalid_q       <= 1'b0;
            arready_q       <= 1'b0;
            rvalid_q        <= 1'b0;
            rready_q        <= 1'b0;
            rlast_q         <= 1'b0;
            awlen_q         <= '0;
            arlen_q         <= '0;
            awid_q          <= '0;
            bid_q           <= '0;
            arid_q          <= '0;
            rid_q           <= '0;
            aw_payload_q    <= '0;
            w_payload_q     <= '0;
            b_payload_q     <= '0;
            ar_payload_q    <= '0;
            r_payload_q     <= '0;
            write_open      <= 1'b0;
            write_data_done <= 1'b0;
            b_response_seen <= 1'b0;
            write_beats_rem <= '0;
            write_id        <= '0;
            read_open       <= 1'b0;
            read_beats_rem  <= '0;
            read_id         <= '0;
        end else begin
            if (awvalid_q && !awready_q) begin
                assert (bus.awvalid &&
                        {bus.awid, bus.awaddr, bus.awlen, bus.awsize,
                         bus.awburst, bus.awlock, bus.awcache, bus.awprot,
                         bus.awqos, bus.awregion} == aw_payload_q)
                    else $error("AXI: AW payload changed while stalled");
            end
            if (wvalid_q && !wready_q) begin
                assert (bus.wvalid &&
                        {bus.wdata, bus.wstrb, bus.wlast} == w_payload_q)
                    else $error("AXI: W payload changed while stalled");
            end
            if (bvalid_q && !bready_q) begin
                assert (bus.bvalid &&
                        {bus.bid, bus.bresp} == b_payload_q)
                    else $error("AXI: B payload changed while stalled");
            end
            if (arvalid_q && !arready_q) begin
                assert (bus.arvalid &&
                        {bus.arid, bus.araddr, bus.arlen, bus.arsize,
                         bus.arburst, bus.arlock, bus.arcache, bus.arprot,
                         bus.arqos, bus.arregion} == ar_payload_q)
                    else $error("AXI: AR payload changed while stalled");
            end
            if (rvalid_q && !rready_q) begin
                assert (bus.rvalid &&
                        {bus.rid, bus.rdata, bus.rresp, bus.rlast} ==
                        r_payload_q)
                    else $error("AXI: R payload changed while stalled");
            end

            if (awvalid_q && awready_q) begin
                assert (!write_open && !write_data_done)
                    else $error("AXI: multiple outstanding writes");
                write_open      <= 1'b1;
                write_beats_rem <= {1'b0, awlen_q} + 9'd1;
                write_id        <= awid_q;
            end

            if (wvalid_q && wready_q) begin
                assert (write_open)
                    else $error("AXI: W handshake without accepted AW");
                if (CHECK_WLAST) begin
                    assert (wlast_q == (write_beats_rem == 9'd1))
                        else $error("AXI: WLAST does not match AWLEN");
                end
                if (write_beats_rem == 9'd1) begin
                    write_open      <= 1'b0;
                    write_data_done <= 1'b1;
                    write_beats_rem <= '0;
                end else begin
                    write_beats_rem <= write_beats_rem - 9'd1;
                end
            end

            if (bvalid_q && !b_response_seen) begin
                assert (write_data_done)
                    else $error("AXI: BVALID asserted before all W beats");
                assert (bid_q == write_id)
                    else $error("AXI: BID does not match AWID");
                b_response_seen <= 1'b1;
            end
            if (bvalid_q && bready_q)
                write_data_done <= 1'b0;
            if (!bvalid_q)
                b_response_seen <= 1'b0;

            if (arvalid_q && arready_q) begin
                assert (!read_open)
                    else $error("AXI: multiple outstanding reads");
                read_open      <= 1'b1;
                read_beats_rem <= {1'b0, arlen_q} + 9'd1;
                read_id        <= arid_q;
            end

            if (rvalid_q) begin
                assert (read_open)
                    else $error("AXI: RVALID asserted without accepted AR");
                assert (rid_q == read_id)
                    else $error("AXI: RID does not match ARID");
                assert (rlast_q == (read_beats_rem == 9'd1))
                    else $error("AXI: RLAST does not match ARLEN");
            end
            if (rvalid_q && rready_q) begin
                if (read_beats_rem == 9'd1) begin
                    read_open      <= 1'b0;
                    read_beats_rem <= '0;
                end else begin
                    read_beats_rem <= read_beats_rem - 9'd1;
                end
            end

            awvalid_q <= bus.awvalid;
            awready_q <= bus.awready;
            wvalid_q  <= bus.wvalid;
            wready_q  <= bus.wready;
            wlast_q   <= bus.wlast;
            bvalid_q  <= bus.bvalid;
            bready_q  <= bus.bready;
            arvalid_q <= bus.arvalid;
            arready_q <= bus.arready;
            rvalid_q  <= bus.rvalid;
            rready_q  <= bus.rready;
            rlast_q   <= bus.rlast;
            awlen_q   <= bus.awlen;
            arlen_q   <= bus.arlen;
            awid_q    <= bus.awid;
            bid_q     <= bus.bid;
            arid_q    <= bus.arid;
            rid_q     <= bus.rid;
            aw_payload_q <= {bus.awid, bus.awaddr, bus.awlen, bus.awsize,
                             bus.awburst, bus.awlock, bus.awcache, bus.awprot,
                             bus.awqos, bus.awregion};
            w_payload_q  <= {bus.wdata, bus.wstrb, bus.wlast};
            b_payload_q  <= {bus.bid, bus.bresp};
            ar_payload_q <= {bus.arid, bus.araddr, bus.arlen, bus.arsize,
                             bus.arburst, bus.arlock, bus.arcache, bus.arprot,
                             bus.arqos, bus.arregion};
            r_payload_q  <= {bus.rid, bus.rdata, bus.rresp, bus.rlast};
        end
    end

endmodule
