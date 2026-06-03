// Directed tests: AXI4-Lite SRAM slave + master BFM.
// `timescale: see tb/timescale.v (compiled first).

import axi_pkg::*;

module axi_lite_sram_tb;

    localparam int unsigned DATA_WIDTH = 64;
    localparam int unsigned SRAM_DEPTH = 256;
    localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;

    logic clk;
    logic rst_n;

    axi_lite_if #(.DATA_WIDTH(DATA_WIDTH)) bus (clk, rst_n);

    axi_lite_sram #(
        .DATA_WIDTH (DATA_WIDTH),
        .SRAM_DEPTH (SRAM_DEPTH)
    ) dut (
        .clk   (clk),
        .rst_n (rst_n),
        .bus   (bus)
    );

    axi_master_bfm #(
        .DATA_WIDTH (DATA_WIDTH)
    ) bfm (
        .clk   (clk),
        .rst_n (rst_n),
        .bus   (bus)
    );

    axi_lite_assertions #(
        .DATA_WIDTH (DATA_WIDTH)
    ) u_assert (
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

    task automatic check_val(
        input string                 name,
        input bit                    ok,
        input logic [DATA_WIDTH-1:0] gold,
        input logic [DATA_WIDTH-1:0] got
    );
        if (ok) begin
            pass_cnt++;
            $display("[PASS] %s", name);
        end else begin
            fail_cnt++;
            $display("[FAIL] %s gold=0x%016h got=0x%016h", name, gold, got);
        end
    endtask

    initial begin
        pass_cnt = 0;
        fail_cnt = 0;

        clk   = 1'b0;
        rst_n = 1'b0;
        forever #5 clk = ~clk;
    end

    initial begin
        logic [63:0] rd;
        bit          ok;

        @(posedge clk);
        rst_n = 1'b0;
        repeat (4) @(posedge clk);
        rst_n = 1'b1;
        bfm.wait_reset_release();
        bfm.drive_idle();

        // Test 1: basic write / read
        bfm.write(64'h100, 64'h0000_0000_DEAD_BEEF, {STRB_WIDTH{1'b1}}, ok);
        check("basic_write", ok);
        bfm.read(64'h100, rd, ok);
        check_val("basic_read", ok && (rd == 64'h0000_0000_DEAD_BEEF), 64'h0000_0000_DEAD_BEEF, rd);

        // Test 2: aligned address
        bfm.write_read_check(64'h108, 64'hCAFE_BABE_1234_5678, {STRB_WIDTH{1'b1}}, ok);
        check("aligned_write_read", ok);

        // Test 3: partial write lower 32 bits
        bfm.write(64'h110, 64'hFFFF_FFFF_AAAA_AAAA, 8'h0F, ok);
        check("partial_write_lo", ok);
        bfm.read(64'h110, rd, ok);
        check_val("partial_read_lo", ok && (rd[31:0] == 32'hAAAA_AAAA), 64'h0000_0000_AAAA_AAAA, rd);

        // Test 4: back-to-back writes
        bfm.write(64'h200, 64'h1111, {STRB_WIDTH{1'b1}}, ok);
        bfm.write(64'h208, 64'h2222, {STRB_WIDTH{1'b1}}, ok);
        bfm.read(64'h200, rd, ok);
        check_val("bb_write_0", ok && (rd == 64'h1111), 64'h1111, rd);
        bfm.read(64'h208, rd, ok);
        check_val("bb_write_1", ok && (rd == 64'h2222), 64'h2222, rd);

        // Test 5: read before write returns zero
        bfm.read(64'h300, rd, ok);
        check_val("read_uninit", ok && (rd == 64'h0), 64'h0, rd);

        // Test 6: unaligned address -> SLVERR on write
        begin
            logic [1:0] bresp;
            bfm.write_get_bresp(64'h105, 64'h1, {STRB_WIDTH{1'b1}}, bresp, ok);
            check("unaligned_write_slverr", ok && (bresp == AXI_RESP_SLVERR));
        end

        // Test 7: out-of-range address -> DECERR on write
        begin
            logic [1:0] bresp;
            bfm.write_get_bresp(64'h2000, 64'h2, {STRB_WIDTH{1'b1}}, bresp, ok);
            check("oor_write_decerr", ok && (bresp == AXI_RESP_DECERR));
        end

        // Test 8: out-of-range address -> DECERR on read
        begin
            logic [1:0] rresp;
            bfm.read_get_rresp(64'h2000, rd, rresp, ok);
            check("oor_read_decerr", ok && (rresp == AXI_RESP_DECERR));
        end

        repeat (8) @(posedge clk);
        $display("SUMMARY pass=%0d fail=%0d", pass_cnt, fail_cnt);
        if (fail_cnt != 0)
            $fatal(1, "axi_lite_sram_tb failed");
        $finish;
    end

endmodule
