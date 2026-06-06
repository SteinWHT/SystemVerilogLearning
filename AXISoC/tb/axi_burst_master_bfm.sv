module axi_burst_master_bfm #(
    parameter int unsigned ADDR_WIDTH     = axi_pkg::AXI_ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH     = axi_pkg::AXI_DATA_WIDTH,
    parameter int unsigned ID_WIDTH       = axi_pkg::AXI_ID_WIDTH,
    parameter int unsigned DEFAULT_ID     = 0,
    parameter int unsigned MAX_BEATS      = 256,
    parameter int unsigned TIMEOUT_CYCLES = 2000
) (
    input  logic clk,
    input  logic rst_n,
    axi_if.master bus
);

    import axi_pkg::*;

    localparam int unsigned STRB_WIDTH  = DATA_WIDTH / 8;
    localparam logic [2:0]  AXSIZE_FULL = 3'($clog2(STRB_WIDTH));

    task automatic wait_reset_release();
        while (!rst_n)
            @(posedge clk);
        @(posedge clk);
    endtask

    task automatic drive_idle();
        bus.awid     = ID_WIDTH'(DEFAULT_ID);
        bus.awaddr   = '0;
        bus.awlen    = '0;
        bus.awsize   = AXSIZE_FULL;
        bus.awburst  = AXI_BURST_INCR;
        bus.awlock   = 1'b0;
        bus.awcache  = '0;
        bus.awprot   = '0;
        bus.awqos    = '0;
        bus.awregion = '0;
        bus.awvalid  = 1'b0;
        bus.wdata    = '0;
        bus.wstrb    = '0;
        bus.wlast    = 1'b0;
        bus.wvalid   = 1'b0;
        bus.bready   = 1'b1;
        bus.arid     = ID_WIDTH'(DEFAULT_ID);
        bus.araddr   = '0;
        bus.arlen    = '0;
        bus.arsize   = AXSIZE_FULL;
        bus.arburst  = AXI_BURST_INCR;
        bus.arlock   = 1'b0;
        bus.arcache  = '0;
        bus.arprot   = '0;
        bus.arqos    = '0;
        bus.arregion = '0;
        bus.arvalid  = 1'b0;
        bus.rready   = 1'b1;
    endtask

    task automatic send_aw_ex(
        input  logic [ADDR_WIDTH-1:0] addr,
        input  logic [7:0]            len,
        input  logic [2:0]            size,
        input  axi_burst_e            burst,
        input  logic [ID_WIDTH-1:0]   id,
        output bit                    ok
    );
        int unsigned cycles;

        ok = 1'b0;
        @(posedge clk);
        #1ps;
        bus.awid     = id;
        bus.awaddr   = addr;
        bus.awlen    = len;
        bus.awsize   = size;
        bus.awburst  = burst;
        bus.awlock   = 1'b0;
        bus.awcache  = '0;
        bus.awprot   = '0;
        bus.awqos    = '0;
        bus.awregion = '0;
        bus.awvalid  = 1'b1;

        for (cycles = 0; cycles < TIMEOUT_CYCLES; cycles++) begin
            @(negedge clk);
            if (bus.awready) begin
                @(posedge clk);
                #1ps;
                bus.awvalid = 1'b0;
                ok = 1'b1;
                return;
            end
        end
        @(posedge clk);
        #1ps;
        bus.awvalid = 1'b0;
    endtask

    task automatic send_aw(
        input  logic [ADDR_WIDTH-1:0] addr,
        input  logic [7:0]            len,
        input  axi_burst_e            burst,
        output bit                    ok
    );
        send_aw_ex(addr, len, AXSIZE_FULL, burst,
                   ID_WIDTH'(DEFAULT_ID), ok);
    endtask

    task automatic send_ar_ex(
        input  logic [ADDR_WIDTH-1:0] addr,
        input  logic [7:0]            len,
        input  logic [2:0]            size,
        input  axi_burst_e            burst,
        input  logic [ID_WIDTH-1:0]   id,
        output bit                    ok
    );
        int unsigned cycles;

        ok = 1'b0;
        @(posedge clk);
        #1ps;
        bus.arid     = id;
        bus.araddr   = addr;
        bus.arlen    = len;
        bus.arsize   = size;
        bus.arburst  = burst;
        bus.arlock   = 1'b0;
        bus.arcache  = '0;
        bus.arprot   = '0;
        bus.arqos    = '0;
        bus.arregion = '0;
        bus.arvalid  = 1'b1;

        for (cycles = 0; cycles < TIMEOUT_CYCLES; cycles++) begin
            @(negedge clk);
            if (bus.arready) begin
                @(posedge clk);
                #1ps;
                bus.arvalid = 1'b0;
                ok = 1'b1;
                return;
            end
        end
        @(posedge clk);
        #1ps;
        bus.arvalid = 1'b0;
    endtask

    task automatic send_ar(
        input  logic [ADDR_WIDTH-1:0] addr,
        input  logic [7:0]            len,
        input  axi_burst_e            burst,
        output bit                    ok
    );
        send_ar_ex(addr, len, AXSIZE_FULL, burst,
                   ID_WIDTH'(DEFAULT_ID), ok);
    endtask

    task automatic send_w_beat_strb(
        input  logic [DATA_WIDTH-1:0] data,
        input  logic [STRB_WIDTH-1:0] strb,
        input  bit                    last,
        output bit                    ok
    );
        int unsigned cycles;

        ok = 1'b0;
        @(posedge clk);
        #1ps;
        bus.wdata  = data;
        bus.wstrb  = strb;
        bus.wlast  = last;
        bus.wvalid = 1'b1;

        for (cycles = 0; cycles < TIMEOUT_CYCLES; cycles++) begin
            @(negedge clk);
            if (bus.wready) begin
                @(posedge clk);
                #1ps;
                bus.wvalid = 1'b0;
                bus.wlast  = 1'b0;
                ok = 1'b1;
                return;
            end
        end
        @(posedge clk);
        #1ps;
        bus.wvalid = 1'b0;
        bus.wlast  = 1'b0;
    endtask

    task automatic send_w_beat(
        input  logic [DATA_WIDTH-1:0] data,
        input  bit                    last,
        output bit                    ok
    );
        send_w_beat_strb(data, {STRB_WIDTH{1'b1}}, last, ok);
    endtask

    task automatic wait_bvalid_resp(
        output bit                   ok,
        output logic [1:0]           resp
    );
        int unsigned cycles;

        ok   = 1'b0;
        resp = AXI_RESP_OKAY;
        for (cycles = 0; cycles < TIMEOUT_CYCLES; cycles++) begin
            @(negedge clk);
            if (bus.bvalid && bus.bready) begin
                resp = bus.bresp;
                ok   = (bus.bid == ID_WIDTH'(DEFAULT_ID));
                @(posedge clk);
                return;
            end
        end
    endtask

    task automatic wait_bvalid(
        output bit         ok,
        output logic [1:0] resp
    );
        wait_bvalid_resp(ok, resp);
        ok = ok && (resp == AXI_RESP_OKAY);
    endtask

    task automatic wait_rbeat(
        output logic [DATA_WIDTH-1:0] data,
        output logic                  last,
        output logic [1:0]            resp,
        output bit                    ok,
        input  bit                    require_okay
    );
        int unsigned cycles;

        ok   = 1'b0;
        data = '0;
        last = 1'b0;
        resp = AXI_RESP_OKAY;
        for (cycles = 0; cycles < TIMEOUT_CYCLES; cycles++) begin
            @(negedge clk);
            if (bus.rvalid && bus.rready) begin
                data = bus.rdata;
                last = bus.rlast;
                resp = bus.rresp;
                ok   = (bus.rid == ID_WIDTH'(DEFAULT_ID));
                if (require_okay)
                    ok = ok && (resp == AXI_RESP_OKAY);
                @(posedge clk);
                return;
            end
        end
    endtask

    task automatic write_burst_ex(
        input  logic [ADDR_WIDTH-1:0] addr,
        input  logic [7:0]            len,
        input  logic [2:0]            size,
        input  axi_burst_e            burst,
        input  logic [DATA_WIDTH-1:0] data[],
        input  logic [STRB_WIDTH-1:0] strb[],
        output logic [1:0]            bresp,
        output bit                    ok
    );
        bit ok_aw;
        bit ok_w;
        bit ok_b;
        int unsigned beats;

        beats = burst_beats(len);
        ok    = (beats <= MAX_BEATS) &&
                (data.size() >= beats) && (strb.size() >= beats);
        bresp = AXI_RESP_OKAY;
        if (!ok)
            return;

        send_aw_ex(addr, len, size, burst, ID_WIDTH'(DEFAULT_ID), ok_aw);
        ok = ok_aw;
        for (int i = 0; i < beats; i++) begin
            send_w_beat_strb(data[i], strb[i], i == beats - 1, ok_w);
            ok = ok && ok_w;
        end
        wait_bvalid_resp(ok_b, bresp);
        ok = ok && ok_b;
    endtask

    task automatic write_burst_bresp(
        input  logic [ADDR_WIDTH-1:0] addr,
        input  logic [7:0]            len,
        input  axi_burst_e            burst,
        input  logic [DATA_WIDTH-1:0] data[],
        output logic [1:0]            bresp,
        output bit                    ok
    );
        logic [STRB_WIDTH-1:0] strb[];
        int unsigned beats;

        beats = burst_beats(len);
        strb  = new[beats];
        foreach (strb[i])
            strb[i] = '1;
        write_burst_ex(addr, len, AXSIZE_FULL, burst, data, strb,
                       bresp, ok);
    endtask

    task automatic write_burst(
        input  logic [ADDR_WIDTH-1:0] addr,
        input  logic [7:0]            len,
        input  axi_burst_e            burst,
        input  logic [DATA_WIDTH-1:0] data[],
        output bit                    ok
    );
        logic [1:0] bresp;

        write_burst_bresp(addr, len, burst, data, bresp, ok);
        ok = ok && (bresp == AXI_RESP_OKAY);
    endtask

    task automatic read_burst_ex(
        input  logic [ADDR_WIDTH-1:0] addr,
        input  logic [7:0]            len,
        input  logic [2:0]            size,
        input  axi_burst_e            burst,
        output logic [DATA_WIDTH-1:0] data[],
        output logic [1:0]            first_rresp,
        output bit                    ok,
        input  bit                    require_okay
    );
        bit ok_ar;
        bit ok_r;
        logic [1:0] resp;
        logic last;
        int unsigned beats;

        beats       = burst_beats(len);
        data        = new[beats];
        first_rresp = AXI_RESP_OKAY;
        ok          = beats <= MAX_BEATS;
        if (!ok)
            return;

        send_ar_ex(addr, len, size, burst, ID_WIDTH'(DEFAULT_ID), ok_ar);
        ok = ok_ar;
        for (int i = 0; i < beats; i++) begin
            wait_rbeat(data[i], last, resp, ok_r, require_okay);
            if (i == 0)
                first_rresp = resp;
            ok = ok && ok_r && (last == (i == beats - 1));
        end
    endtask

    task automatic read_burst(
        input  logic [ADDR_WIDTH-1:0] addr,
        input  logic [7:0]            len,
        input  axi_burst_e            burst,
        output logic [DATA_WIDTH-1:0] data[],
        output bit                    ok
    );
        logic [1:0] first_rresp;

        read_burst_ex(addr, len, AXSIZE_FULL, burst, data,
                      first_rresp, ok, 1'b1);
        ok = ok && (first_rresp == AXI_RESP_OKAY);
    endtask

    task automatic read_burst_first_rresp(
        input  logic [ADDR_WIDTH-1:0] addr,
        input  logic [7:0]            len,
        input  axi_burst_e            burst,
        output logic [1:0]            rresp,
        output bit                    ok
    );
        logic [DATA_WIDTH-1:0] data[];

        read_burst_ex(addr, len, AXSIZE_FULL, burst, data,
                      rresp, ok, 1'b0);
    endtask

    task automatic write(
        input  logic [ADDR_WIDTH-1:0] addr,
        input  logic [DATA_WIDTH-1:0] data,
        input  logic [STRB_WIDTH-1:0] strb,
        output bit                    ok
    );
        bit ok_aw;
        bit ok_w;
        bit ok_b;
        logic [1:0] bresp;

        send_aw(addr, 8'd0, AXI_BURST_INCR, ok_aw);
        send_w_beat_strb(data, strb, 1'b1, ok_w);
        wait_bvalid(ok_b, bresp);
        ok = ok_aw && ok_w && ok_b && (bresp == AXI_RESP_OKAY);
    endtask

    task automatic read(
        input  logic [ADDR_WIDTH-1:0] addr,
        output logic [DATA_WIDTH-1:0] data,
        output bit                    ok
    );
        logic [DATA_WIDTH-1:0] burst_data[];

        read_burst(addr, 8'd0, AXI_BURST_INCR, burst_data, ok);
        if (ok)
            data = burst_data[0];
    endtask

    initial drive_idle();

endmodule
