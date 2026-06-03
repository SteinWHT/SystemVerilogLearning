// Full AXI4 master BFM with INCR/FIXED burst write and read tasks.

import axi_pkg::*;

module axi_burst_master_bfm #(
    parameter int unsigned ADDR_WIDTH     = AXI_ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH     = AXI_DATA_WIDTH,
    parameter int unsigned MAX_BEATS      = 64,
    parameter int unsigned TIMEOUT_CYCLES = 2000
) (
    input  logic clk,
    input  logic rst_n,
    axi_if.master bus
);

    localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;
    localparam logic [2:0]  AXSIZE_FULL = 3'd3;  // 8 bytes (64-bit bus)

    task automatic wait_reset_release();
        while (!rst_n)
            @(posedge clk);
        @(posedge clk);
    endtask

    task automatic drive_idle();
        bus.awvalid  <= 1'b0;
        bus.wvalid   <= 1'b0;
        bus.bready   <= 1'b1;
        bus.arvalid  <= 1'b0;
        bus.awsize   <= AXSIZE_FULL;
        bus.arsize   <= AXSIZE_FULL;
        bus.awburst  <= 2'(AXI_BURST_INCR);
        bus.arburst  <= 2'(AXI_BURST_INCR);
        bus.awprot   <= '0;
        bus.arprot   <= '0;
        bus.wlast    <= 1'b0;
        bus.rready   <= 1'b1;
    endtask

    // AW: addr/len stable two cycles before valid; hold until handshake.
    task automatic send_aw(
        input  logic [ADDR_WIDTH-1:0] addr,
        input  logic [7:0]            len,
        input  axi_burst_e            burst,
        output bit                    ok
    );
        int unsigned cyc;
        ok  = 1'b1;
        cyc = 0;
        bus.awaddr  <= addr;
        bus.awlen   <= len;
        bus.awsize  <= AXSIZE_FULL;
        bus.awburst <= 2'(burst);
        bus.awprot  <= '0;
        bus.awvalid <= 1'b0;
        @(posedge clk);
        @(posedge clk);
        // Re-drive burst/len immediately before VALID (interface outputs can
        // otherwise appear as FIXED at the slave's ARREADY/AWREADY sample).
        bus.awburst <= 2'(burst);
        bus.awlen   <= len;
        bus.awaddr  <= addr;
        bus.awsize  <= AXSIZE_FULL;
        bus.awvalid <= 1'b1;
        while (!(bus.awvalid && bus.awready)) begin
            @(posedge clk);
            cyc++;
            if (cyc > TIMEOUT_CYCLES) begin
                ok = 1'b0;
                bus.awvalid <= 1'b0;
                return;
            end
        end
        bus.awvalid <= 1'b0;
    endtask

    task automatic send_ar(
        input  logic [ADDR_WIDTH-1:0] addr,
        input  logic [7:0]            len,
        input  axi_burst_e            burst,
        output bit                    ok
    );
        int unsigned cyc;
        ok  = 1'b1;
        cyc = 0;
        bus.araddr  <= addr;
        bus.arlen   <= len;
        bus.arsize  <= AXSIZE_FULL;
        bus.arburst <= 2'(burst);
        bus.arprot  <= '0;
        bus.arvalid <= 1'b0;
        @(posedge clk);
        @(posedge clk);
        bus.arburst <= 2'(burst);
        bus.arlen   <= len;
        bus.araddr  <= addr;
        bus.arsize  <= AXSIZE_FULL;
        bus.arvalid <= 1'b1;
        while (!(bus.arvalid && bus.arready)) begin
            @(posedge clk);
            cyc++;
            if (cyc > TIMEOUT_CYCLES) begin
                ok = 1'b0;
                bus.arvalid <= 1'b0;
                return;
            end
        end
        bus.arvalid <= 1'b0;
    endtask

    task automatic send_w_beat(
        input  logic [DATA_WIDTH-1:0] data,
        input  bit                    last,
        output bit                    ok
    );
        int unsigned cyc;
        ok  = 1'b1;
        cyc = 0;
        bus.wdata  <= data;
        bus.wstrb  <= {STRB_WIDTH{1'b1}};
        bus.wlast  <= last;
        bus.wvalid <= 1'b0;
        @(posedge clk);
        bus.wvalid <= 1'b1;
        while (!(bus.wvalid && bus.wready)) begin
            @(posedge clk);
            cyc++;
            if (cyc > TIMEOUT_CYCLES) begin
                ok = 1'b0;
                bus.wvalid <= 1'b0;
                bus.wlast  <= 1'b0;
                return;
            end
        end
        bus.wvalid <= 1'b0;
        bus.wlast  <= 1'b0;
    endtask

    task automatic wait_bvalid(output bit ok, output logic [1:0] resp);
        wait_bvalid_resp(ok, resp);
        if (resp != AXI_RESP_OKAY)
            ok = 1'b0;
    endtask

    task automatic wait_bvalid_resp(output bit ok, output logic [1:0] resp);
        int unsigned cyc;
        ok  = 1'b1;
        cyc = 0;
        do begin
            @(posedge clk);
            cyc++;
            if (cyc > TIMEOUT_CYCLES) begin
                ok = 1'b0;
                resp = AXI_RESP_OKAY;
                return;
            end
        end while (!bus.bvalid);
        resp = bus.bresp;
    endtask

    // Caller must hold RREADY high for the entire read data phase (see read_burst).
    // Keeps RVALID stable per AXI (no RVALID high while RREADY low for a cycle).
    task automatic wait_rbeat(
        output logic [DATA_WIDTH-1:0] data,
        output logic                  last,
        output logic [1:0]            resp,
        output bit                    ok,
        input  bit                    require_okay
    );
        int unsigned cyc;
        ok  = 1'b1;
        cyc = 0;

        while (!bus.rvalid) begin
            @(posedge clk);
            cyc++;
            if (cyc > TIMEOUT_CYCLES) begin
                ok = 1'b0;
                return;
            end
        end

        data = bus.rdata;
        last = bus.rlast;
        resp = bus.rresp;
        if (require_okay && (resp != AXI_RESP_OKAY))
            ok = 1'b0;

        while (bus.rvalid) begin
            @(posedge clk);
            cyc++;
            if (cyc > TIMEOUT_CYCLES) begin
                ok = 1'b0;
                return;
            end
        end
    endtask

    task automatic write_burst_bresp(
        input  logic [ADDR_WIDTH-1:0]     addr,
        input  logic [7:0]                len,
        input  axi_burst_e                burst,
        input  logic [DATA_WIDTH-1:0]     data[],
        output logic [1:0]                bresp,
        output bit                        ok
    );
        bit          ok_aw, ok_w, ok_b;
        int unsigned beats;
        ok    = 1'b1;
        beats = int'(len) + 1;
        if (beats > MAX_BEATS) begin
            ok = 1'b0;
            bresp = AXI_RESP_OKAY;
            return;
        end

        send_aw(addr, len, burst, ok_aw);
        ok = ok_aw;
        for (int i = 0; i < beats; i++) begin
            send_w_beat(data[i], (i == beats - 1), ok_w);
            ok = ok && ok_w;
        end
        wait_bvalid_resp(ok_b, bresp);
        ok = ok && ok_b;
    endtask

    task automatic read_burst_first_rresp(
        input  logic [ADDR_WIDTH-1:0] addr,
        input  logic [7:0]            len,
        input  axi_burst_e            burst,
        output logic [1:0]            rresp,
        output bit                    ok
    );
        bit          ok_ar, ok_r;
        logic [DATA_WIDTH-1:0] dummy;
        logic                  rlast;
        ok = 1'b1;

        bus.rready = 1'b0;
        send_ar(addr, len, burst, ok_ar);
        bus.rready = 1'b1;
        wait_rbeat(dummy, rlast, rresp, ok_r, 1'b0);
        ok = ok_ar && ok_r;
    endtask

    task automatic write_burst(
        input  logic [ADDR_WIDTH-1:0]     addr,
        input  logic [7:0]                len,
        input  axi_burst_e                burst,
        input  logic [DATA_WIDTH-1:0]     data[],
        output bit                        ok
    );
        bit          ok_aw, ok_w, ok_b;
        logic [1:0]  bresp;
        int unsigned beats;
        ok    = 1'b1;
        beats = int'(len) + 1;
        if (beats > MAX_BEATS) begin
            ok = 1'b0;
            return;
        end

        send_aw(addr, len, burst, ok_aw);
        ok = ok_aw;
        for (int i = 0; i < beats; i++) begin
            send_w_beat(data[i], (i == beats - 1), ok_w);
            ok = ok && ok_w;
        end
        wait_bvalid(ok_b, bresp);
        ok = ok && ok_b;
    endtask

    task automatic read_burst(
        input  logic [ADDR_WIDTH-1:0] addr,
        input  logic [7:0]            len,
        input  axi_burst_e            burst,
        output logic [DATA_WIDTH-1:0] data[],
        output bit                    ok
    );
        bit          ok_ar, ok_r;
        logic [1:0]  rresp;
        logic        rlast;
        int unsigned beats;
        ok    = 1'b1;
        beats = int'(len) + 1;
        if (beats > MAX_BEATS) begin
            ok = 1'b0;
            return;
        end
        data = new[beats];

        bus.rready = 1'b0;
        send_ar(addr, len, burst, ok_ar);
        bus.rready = 1'b1;
        ok = ok_ar;
        for (int i = 0; i < beats; i++) begin
            wait_rbeat(data[i], rlast, rresp, ok_r, 1'b1);
            ok = ok && ok_r;
            if (i == beats - 1) begin
                if (!rlast)
                    ok = 1'b0;
            end else if (rlast) begin
                ok = 1'b0;
            end
        end
    endtask

    task automatic write(
        input  logic [ADDR_WIDTH-1:0] addr,
        input  logic [DATA_WIDTH-1:0] data,
        input  logic [STRB_WIDTH-1:0] strb,
        output bit                    ok
    );
        logic [DATA_WIDTH-1:0] d[1];
        d[0] = data;
        write_burst(addr, 8'd0, AXI_BURST_INCR, d, ok);
    endtask

    task automatic read(
        input  logic [ADDR_WIDTH-1:0] addr,
        output logic [DATA_WIDTH-1:0] data,
        output bit                    ok
    );
        logic [DATA_WIDTH-1:0] d[];
        read_burst(addr, 8'd0, AXI_BURST_INCR, d, ok);
        if (ok && d.size() == 1)
            data = d[0];
    endtask

    initial begin
        drive_idle();
    end

endmodule
