// Reusable AXI4-Lite master BFM (testbench / future UVM driver backend).

import axi_pkg::*;

module axi_master_bfm #(
    parameter int unsigned ADDR_WIDTH = AXI_ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH = AXI_DATA_WIDTH,
    parameter int unsigned TIMEOUT_CYCLES = 1000
) (
    input  logic clk,
    input  logic rst_n,
    axi_lite_if.master bus
);

    localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;

    task automatic wait_reset_release();
        while (!rst_n)
            @(posedge clk);
        @(posedge clk);
    endtask

    task automatic drive_idle();
        bus.awvalid <= 1'b0;
        bus.wvalid  <= 1'b0;
        bus.bready  <= 1'b1;
        bus.arvalid <= 1'b0;
        bus.rready  <= 1'b1;
        bus.awprot  <= '0;
        bus.arprot  <= '0;
    endtask

    task automatic handshake_aw(
        input logic [ADDR_WIDTH-1:0] addr,
        output bit                   ok
    );
        int unsigned cyc;
        ok = 1'b1;
        bus.awaddr  <= addr;
        bus.awvalid <= 1'b1;
        cyc = 0;
        do begin
            @(posedge clk);
            cyc++;
            if (cyc > TIMEOUT_CYCLES) begin
                ok = 1'b0;
                bus.awvalid <= 1'b0;
                return;
            end
        end while (!bus.awready);
        bus.awvalid <= 1'b0;
    endtask

    task automatic handshake_w(
        input logic [DATA_WIDTH-1:0] data,
        input logic [STRB_WIDTH-1:0] strb,
        output bit                   ok
    );
        int unsigned cyc;
        ok = 1'b1;
        bus.wdata  <= data;
        bus.wstrb  <= strb;
        bus.wvalid <= 1'b1;
        cyc = 0;
        do begin
            @(posedge clk);
            cyc++;
            if (cyc > TIMEOUT_CYCLES) begin
                ok = 1'b0;
                bus.wvalid <= 1'b0;
                return;
            end
        end while (!bus.wready);
        bus.wvalid <= 1'b0;
    endtask

    task automatic handshake_b(output bit ok);
        logic [1:0] resp;
        handshake_b_resp(ok, resp);
        if (resp != AXI_RESP_OKAY)
            ok = 1'b0;
    endtask

    task automatic handshake_b_resp(output bit ok, output logic [1:0] resp);
        int unsigned cyc;
        ok = 1'b1;
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

    task automatic handshake_r_resp(
        output logic [DATA_WIDTH-1:0] data,
        output logic [1:0]            resp,
        output bit                    ok
    );
        int unsigned cyc;
        ok = 1'b1;
        cyc = 0;
        do begin
            @(posedge clk);
            cyc++;
            if (cyc > TIMEOUT_CYCLES) begin
                ok = 1'b0;
                resp = AXI_RESP_OKAY;
                return;
            end
        end while (!bus.rvalid);
        data = bus.rdata;
        resp = bus.rresp;
    endtask

    task automatic write_get_bresp(
        input  logic [ADDR_WIDTH-1:0] addr,
        input  logic [DATA_WIDTH-1:0] data,
        input  logic [STRB_WIDTH-1:0] strb,
        output logic [1:0]            bresp,
        output bit                    ok
    );
        bit ok_aw, ok_w, ok_b;
        ok = 1'b1;
        fork
            begin handshake_aw(addr, ok_aw); end
            begin handshake_w(data, strb, ok_w); end
        join
        handshake_b_resp(ok_b, bresp);
        ok = ok_aw && ok_w && ok_b;
    endtask

    task automatic read_get_rresp(
        input  logic [ADDR_WIDTH-1:0] addr,
        output logic [DATA_WIDTH-1:0] data,
        output logic [1:0]            rresp,
        output bit                    ok
    );
        bit ok_ar, ok_r;
        handshake_ar(addr, ok_ar);
        handshake_r_resp(data, rresp, ok_r);
        ok = ok_ar && ok_r;
    endtask

    task automatic handshake_ar(
        input logic [ADDR_WIDTH-1:0] addr,
        output bit                   ok
    );
        int unsigned cyc;
        ok = 1'b1;
        bus.araddr  <= addr;
        bus.arvalid <= 1'b1;
        cyc = 0;
        do begin
            @(posedge clk);
            cyc++;
            if (cyc > TIMEOUT_CYCLES) begin
                ok = 1'b0;
                bus.arvalid <= 1'b0;
                return;
            end
        end while (!bus.arready);
        bus.arvalid <= 1'b0;
    endtask

    task automatic handshake_r(
        output logic [DATA_WIDTH-1:0] data,
        output bit                    ok
    );
        int unsigned cyc;
        ok = 1'b1;
        cyc = 0;
        do begin
            @(posedge clk);
            cyc++;
            if (cyc > TIMEOUT_CYCLES) begin
                ok = 1'b0;
                return;
            end
        end while (!bus.rvalid);
        data = bus.rdata;
        if (bus.rresp != AXI_RESP_OKAY)
            ok = 1'b0;
    endtask

    task automatic write(
        input  logic [ADDR_WIDTH-1:0] addr,
        input  logic [DATA_WIDTH-1:0] data,
        input  logic [STRB_WIDTH-1:0] strb,
        output bit                    ok
    );
        bit ok_aw, ok_w, ok_b;
        ok = 1'b1;
        fork
            begin handshake_aw(addr, ok_aw); end
            begin handshake_w(data, strb, ok_w); end
        join
        handshake_b(ok_b);
        ok = ok_aw && ok_w && ok_b;
    endtask

    task automatic read(
        input  logic [ADDR_WIDTH-1:0] addr,
        output logic [DATA_WIDTH-1:0] data,
        output bit                    ok
    );
        bit ok_ar, ok_r;
        handshake_ar(addr, ok_ar);
        handshake_r(data, ok_r);
        ok = ok_ar && ok_r;
    endtask

    task automatic write_read_check(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] data,
        input logic [STRB_WIDTH-1:0] strb,
        output bit                   ok
    );
        logic [DATA_WIDTH-1:0] rd;
        bit ok_w, ok_r;
        write(addr, data, strb, ok_w);
        read(addr, rd, ok_r);
        ok = ok_w && ok_r && (rd == data);
    endtask

    initial begin
        drive_idle();
    end

endmodule
