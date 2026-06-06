module axi_sram_tb;

    import axi_pkg::*;

    localparam int unsigned ADDR_WIDTH = 32;
    localparam int unsigned DATA_WIDTH = 64;
    localparam int unsigned ID_WIDTH   = 4;
    localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;
    localparam int unsigned SRAM_DEPTH = 2048;

    logic clk;
    logic rst_n;
    logic                  init_en;
    logic [ADDR_WIDTH-1:0] init_word_idx;
    logic [DATA_WIDTH-1:0] init_data;

    axi_if #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH)
    ) bus (clk, rst_n);

    axi_sram #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .SRAM_DEPTH (SRAM_DEPTH)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .init_en       (init_en),
        .init_word_idx (init_word_idx),
        .init_data     (init_data),
        .bus           (bus)
    );

    axi_burst_master_bfm #(
        .ADDR_WIDTH (ADDR_WIDTH),
        .DATA_WIDTH (DATA_WIDTH),
        .ID_WIDTH   (ID_WIDTH),
        .DEFAULT_ID (5),
        .MAX_BEATS  (256)
    ) bfm (
        .clk   (clk),
        .rst_n (rst_n),
        .bus   (bus)
    );

    axi_assertions #(
        .ADDR_WIDTH  (ADDR_WIDTH),
        .DATA_WIDTH  (DATA_WIDTH),
        .ID_WIDTH    (ID_WIDTH),
        .CHECK_WLAST (1'b0)
    ) u_assert (
        .clk   (clk),
        .rst_n (rst_n),
        .bus   (bus)
    );

    int unsigned pass_cnt;
    int unsigned fail_cnt;

    task automatic check(input string name, input bit passed);
        if (passed) begin
            pass_cnt++;
            $display("[PASS] %s", name);
        end else begin
            fail_cnt++;
            $display("[FAIL] %s", name);
        end
    endtask

    task automatic expect_read(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [DATA_WIDTH-1:0] expected,
        input string                 name
    );
        logic [DATA_WIDTH-1:0] data;
        bit ok;

        bfm.read(addr, data, ok);
        check(name, ok && data == expected);
    endtask

    initial begin
        clk = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        logic [DATA_WIDTH-1:0] wr[];
        logic [DATA_WIDTH-1:0] rd[];
        logic [STRB_WIDTH-1:0] strb[];
        logic [1:0] resp;
        bit ok;
        bit ok_aw;
        bit ok_w;
        bit ok_b;

        pass_cnt = 0;
        fail_cnt = 0;
        rst_n    = 1'b0;
        init_en       = 1'b0;
        init_word_idx = '0;
        init_data     = '0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        init_en       = 1'b1;
        init_word_idx = ADDR_WIDTH'(16);
        init_data     = 64'h0123_4567_89AB_CDEF;
        @(posedge clk);
        @(negedge clk);
        init_en       = 1'b0;
        init_word_idx = '0;
        init_data     = '0;
        repeat (2) @(posedge clk);
        @(negedge clk);
        rst_n = 1'b1;
        bfm.wait_reset_release();
        bfm.drive_idle();

        expect_read(32'h0080, 64'h0123_4567_89AB_CDEF,
                    "synchronous_init_port");

        wr = new[1];
        wr[0] = 64'hDEAD_BEEF_CAFE_BABE;
        bfm.write_burst(32'h0000, 8'd0, AXI_BURST_INCR, wr, ok);
        check("single_write_with_id", ok);
        expect_read(32'h0000, wr[0], "single_read_with_id");

        wr = new[8];
        foreach (wr[i])
            wr[i] = 64'hA000_0000_0000_0000 + 64'(i);
        bfm.write_burst(32'h0040, 8'd7, AXI_BURST_INCR, wr, ok);
        check("incr_write_8", ok);
        bfm.read_burst(32'h0040, 8'd7, AXI_BURST_INCR, rd, ok);
        foreach (wr[i])
            ok = ok && (rd[i] == wr[i]);
        check("incr_read_8_back_to_back", ok);

        wr = new[3];
        wr[0] = 64'h1111;
        wr[1] = 64'h2222;
        wr[2] = 64'h3333;
        bfm.write_burst(32'h0100, 8'd2, AXI_BURST_FIXED, wr, ok);
        check("fixed_write", ok);
        expect_read(32'h0100, 64'h3333, "fixed_last_write_wins");

        wr = new[4];
        foreach (wr[i])
            wr[i] = 64'hB000 + 64'(i);
        bfm.write_burst(32'h0138, 8'd3, AXI_BURST_WRAP, wr, ok);
        check("wrap_write_4", ok);
        bfm.read_burst(32'h0138, 8'd3, AXI_BURST_WRAP, rd, ok);
        foreach (wr[i])
            ok = ok && (rd[i] == wr[i]);
        check("wrap_read_4", ok);

        bfm.write(32'h0200, 64'h1122_3344_5566_7788, '1, ok);
        bfm.write(32'h0200, 64'hDEAD_BEEF_AAAA_BBBB, 8'h0f, ok);
        expect_read(32'h0200, 64'h1122_3344_AAAA_BBBB,
                    "partial_write_strobes");

        bfm.write(32'h0208, 64'hCAFE_BABE_1234_5678, '1, ok);
        bfm.write(32'h0208, 64'hFFFF_FFFF_FFFF_FFFF, '0, ok);
        expect_read(32'h0208, 64'hCAFE_BABE_1234_5678,
                    "zero_strobe_is_legal_noop");

        bfm.write(32'h0220, '0, '1, ok);
        wr   = new[1];
        strb = new[1];
        wr[0]   = 64'hDEAD_BEEF_0000_0000;
        strb[0] = 8'hf0;
        bfm.write_burst_ex(32'h0224, 8'd0, 3'd2, AXI_BURST_INCR,
                           wr, strb, resp, ok);
        check("narrow_write_32", ok && resp == AXI_RESP_OKAY);
        bfm.read_burst_ex(32'h0224, 8'd0, 3'd2, AXI_BURST_INCR,
                          rd, resp, ok, 1'b1);
        check("narrow_read_32", ok && rd[0] == wr[0]);

        wr = new[256];
        foreach (wr[i])
            wr[i] = 64'hC000_0000_0000_0000 + 64'(i);
        bfm.write_burst(32'h0800, 8'hff, AXI_BURST_INCR, wr, ok);
        check("max_256_beat_write", ok);
        bfm.read_burst(32'h0800, 8'hff, AXI_BURST_INCR, rd, ok);
        foreach (wr[i])
            ok = ok && (rd[i] == wr[i]);
        check("max_256_beat_read", ok);

        wr = new[2];
        wr[0] = 64'hD1;
        wr[1] = 64'hD2;
        bfm.write_burst(32'h0ff8, 8'd1, AXI_BURST_FIXED, wr, ok);
        check("fixed_near_4k_is_legal", ok);
        expect_read(32'h0ff8, 64'hD2, "fixed_near_4k_data");

        bfm.write_burst_bresp(32'h0ff8, 8'd1, AXI_BURST_INCR,
                              wr, resp, ok);
        check("incr_cross_4k_slverr",
              ok && resp == AXI_RESP_SLVERR);

        wr = new[3];
        foreach (wr[i])
            wr[i] = 64'hE0 + 64'(i);
        bfm.write_burst_bresp(32'h0300, 8'd2, AXI_BURST_WRAP,
                              wr, resp, ok);
        check("illegal_wrap_length_slverr",
              ok && resp == AXI_RESP_SLVERR);

        wr = new[1];
        wr[0] = 64'hF0;
        bfm.write_burst_bresp(32'h4000, 8'd0, AXI_BURST_INCR,
                              wr, resp, ok);
        check("out_of_range_write_decerr",
              ok && resp == AXI_RESP_DECERR);
        bfm.read_burst_first_rresp(32'h4000, 8'd0, AXI_BURST_INCR,
                                   resp, ok);
        check("out_of_range_read_decerr",
              ok && resp == AXI_RESP_DECERR);

        bfm.send_aw(32'h0300, 8'd0, AXI_BURST_INCR, ok_aw);
        bfm.send_w_beat(64'h1234, 1'b0, ok_w);
        bfm.wait_bvalid_resp(ok_b, resp);
        check("missing_wlast_slverr",
              ok_aw && ok_w && ok_b && resp == AXI_RESP_SLVERR);

        bfm.send_aw(32'h0310, 8'd1, AXI_BURST_INCR, ok_aw);
        bfm.send_w_beat(64'h1, 1'b1, ok_w);
        ok = ok_aw && ok_w;
        bfm.send_w_beat(64'h2, 1'b1, ok_w);
        ok = ok && ok_w;
        bfm.wait_bvalid_resp(ok_b, resp);
        check("early_wlast_drained_with_slverr",
              ok && ok_b && resp == AXI_RESP_SLVERR);

        #1ps;
        bus.bready = 1'b0;
        bfm.send_aw(32'h0320, 8'd0, AXI_BURST_INCR, ok_aw);
        bfm.send_w_beat(64'h55AA, 1'b1, ok_w);
        repeat (3) begin
            @(negedge clk);
            ok = bus.bvalid && bus.bid == ID_WIDTH'(5) &&
                 bus.bresp == AXI_RESP_OKAY;
        end
        @(posedge clk);
        #1ps;
        bus.bready = 1'b1;
        bfm.wait_bvalid_resp(ok_b, resp);
        check("b_channel_backpressure_stable",
              ok_aw && ok_w && ok && ok_b && resp == AXI_RESP_OKAY);

        #1ps;
        bus.rready = 1'b0;
        bfm.send_ar(32'h0320, 8'd0, AXI_BURST_INCR, ok_aw);
        repeat (3) begin
            @(negedge clk);
            ok = bus.rvalid && bus.rid == ID_WIDTH'(5) &&
                 bus.rdata == 64'h55AA && bus.rlast;
        end
        @(posedge clk);
        #1ps;
        bus.rready = 1'b1;
        bfm.wait_rbeat(rd[0], ok_w, resp, ok_b, 1'b1);
        check("r_channel_backpressure_stable",
              ok_aw && ok && ok_b && ok_w && rd[0] == 64'h55AA);

        repeat (5) @(posedge clk);
        $display("SUMMARY pass=%0d fail=%0d", pass_cnt, fail_cnt);
        if (fail_cnt != 0)
            $fatal(1, "axi_sram_tb failed");
        $finish;
    end

endmodule
