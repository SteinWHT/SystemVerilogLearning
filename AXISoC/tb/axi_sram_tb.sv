// Directed tests: full AXI4 burst SRAM slave.

// `timescale: see tb/timescale.v

import axi_pkg::*;

module axi_sram_tb;

    localparam int unsigned DATA_WIDTH = 64;
    localparam int unsigned SRAM_DEPTH = 512;
    localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;

    logic clk;
    logic rst_n;

    axi_if #(.DATA_WIDTH(DATA_WIDTH)) bus (clk, rst_n);

    axi_sram #(
        .DATA_WIDTH (DATA_WIDTH),
        .SRAM_DEPTH (SRAM_DEPTH)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .bus   (bus)
    );

    axi_burst_master_bfm #(
        .DATA_WIDTH (DATA_WIDTH),
        .MAX_BEATS  (32)
    ) bfm (
        .clk   (clk),
        .rst_n (rst_n),
        .bus   (bus)
    );

    axi_assertions #(.DATA_WIDTH(DATA_WIDTH)) u_assert (
        .clk   (clk),
        .rst_n (rst_n),
        .bus   (bus)
    );

    int unsigned pass_cnt;
    int unsigned fail_cnt;

    task automatic check(input string name, input bit ok);
        if (ok) begin
            pass_cnt++;
            $display("[PASS] %s", name);
        end else begin
            fail_cnt++;
            $display("[FAIL] %s", name);
        end
    endtask

    function automatic logic [63:0] incr_addr(
        input logic [63:0] addr,
        input int unsigned beat
    );
        return addr + beat * 8;
    endfunction

    initial begin
        pass_cnt = 0;
        fail_cnt = 0;
        clk      = 1'b0;
        rst_n    = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        logic [63:0] wr_data[];
        logic [63:0] rd_data[];
        bit          ok;
        logic [1:0]  resp;
        int unsigned i;

        @(posedge clk);
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        bfm.wait_reset_release();
        bfm.drive_idle();

        // Test 1: single beat (len=0)
        wr_data = new[1];
        wr_data[0] = 64'hDEAD_BEEF_CAFE_BABE;
        bfm.write_burst(64'h000, 8'd0, AXI_BURST_INCR, wr_data, ok);
        check("single_write", ok);
        bfm.read_burst(64'h000, 8'd0, AXI_BURST_INCR, rd_data, ok);
        check("single_read", ok && (rd_data[0] == wr_data[0]));

        // Test 2: INCR burst len=3 (4 beats)
        wr_data = new[4];
        for (i = 0; i < 4; i++)
            wr_data[i] = 64'hA000_0000_0000_0000 + i;
        bfm.write_burst(64'h100, 8'd3, AXI_BURST_INCR, wr_data, ok);
        check("incr_write_4", ok);
        bfm.read_burst(64'h100, 8'd3, AXI_BURST_INCR, rd_data, ok);
        ok = ok && (rd_data.size() == 4);
        for (i = 0; i < 4; i++)
            ok = ok && (rd_data[i] == wr_data[i]);
        check("incr_read_4", ok);

        // Test 3: FIXED burst (2 beats, same address — last write wins)
        wr_data    = new[2];
        wr_data[0] = 64'h1111;
        wr_data[1] = 64'h2222;
        bfm.write_burst(64'h200, 8'd1, AXI_BURST_FIXED, wr_data, ok);
        check("fixed_write", ok);
        bfm.read_burst(64'h200, 8'd0, AXI_BURST_INCR, rd_data, ok);
        check("fixed_read_last_wins", ok && (rd_data[0] == 64'h2222));

        // Test 4: long INCR burst len=7
        wr_data = new[8];
        for (i = 0; i < 8; i++)
            wr_data[i] = 64'hB000 + i;
        bfm.write_burst(64'h300, 8'd7, AXI_BURST_INCR, wr_data, ok);
        check("incr_write_8", ok);
        bfm.read_burst(64'h300, 8'd7, AXI_BURST_INCR, rd_data, ok);
        ok = ok && (rd_data.size() == 8);
        for (i = 0; i < 8; i++)
            ok = ok && (rd_data[i] == wr_data[i]);
        check("incr_read_8", ok);

        // Test 5: WRAP burst rejected (SLVERR on B)
        wr_data    = new[1];
        wr_data[0] = 64'h1;
        begin
            bit ok_aw, ok_w, ok_b;
            bfm.send_aw(64'h400, 8'd0, AXI_BURST_WRAP, ok_aw);
            bfm.send_w_beat(wr_data[0], 1'b1, ok_w);
            bfm.wait_bvalid_resp(ok_b, resp);
            ok = ok_aw && ok_w && ok_b;
        end
        check("wrap_slverr", ok && (resp == AXI_RESP_SLVERR));

        // Test 6: INCR burst crosses 4KB page -> SLVERR
        wr_data    = new[2];
        wr_data[0] = 64'hA;
        wr_data[1] = 64'hB;
        begin
            logic [1:0] bresp;
            bfm.write_burst_bresp(64'h0FF8, 8'd1, AXI_BURST_INCR, wr_data, bresp, ok);
            check("cross_4k_slverr", ok && (bresp == AXI_RESP_SLVERR));
        end

        // Test 7: out-of-range single write -> DECERR
        wr_data    = new[1];
        wr_data[0] = 64'hC;
        begin
            logic [1:0] bresp;
            bfm.write_burst_bresp(64'h2000, 8'd0, AXI_BURST_INCR, wr_data, bresp, ok);
            check("oor_write_decerr", ok && (bresp == AXI_RESP_DECERR));
        end

        // Test 8: out-of-range read -> DECERR on first R beat
        begin
            logic [1:0] rresp;
            bfm.read_burst_first_rresp(64'h2000, 8'd0, AXI_BURST_INCR, rresp, ok);
            check("oor_read_decerr", ok && (rresp == AXI_RESP_DECERR));
        end

        repeat (8) @(posedge clk);
        $display("SUMMARY pass=%0d fail=%0d", pass_cnt, fail_cnt);
        if (fail_cnt != 0)
            $fatal(1, "axi_sram_tb failed");
        $finish;
    end

endmodule
