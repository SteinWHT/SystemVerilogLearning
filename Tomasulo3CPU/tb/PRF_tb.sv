// Physical register file: CDB write, multi-port read, same-cycle CDB bypass.
/* verilator lint_off WIDTH */
// verilog_lint: waive-start explicit-parameter-storage-type
/* verilator lint_off BLKSEQ */
`timescale 1ns/1ps

module PRF_tb;

    parameter int unsigned REG_FILE_DATA_WIDTH     = 64;
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7;

    logic clk;
    logic rst_n;

    logic [PHY_REGISTER_FILE_WIDTH-1:0] rt_sb_phy_addr;
    logic [REG_FILE_DATA_WIDTH-1:0]     rt_sb_data;

    logic [PHY_REGISTER_FILE_WIDTH-1:0] cdb_rd_phy_addr;
    logic [REG_FILE_DATA_WIDTH-1:0]     cdb_rd_data;
    logic                               cdb_reg_write;

    logic [PHY_REGISTER_FILE_WIDTH-1:0] issue_rs_phy_addr_alu;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] issue_rt_phy_addr_alu;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] issue_rs_phy_addr_div;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] issue_rt_phy_addr_div;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] issue_rs_phy_addr_mul;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] issue_rt_phy_addr_mul;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] issue_rs_phy_addr_lsq;

    logic [REG_FILE_DATA_WIDTH-1:0] issue_rs_data_lsq;
    logic [REG_FILE_DATA_WIDTH-1:0] exe_rs_data_alu;
    logic [REG_FILE_DATA_WIDTH-1:0] exe_rt_data_alu;
    logic [REG_FILE_DATA_WIDTH-1:0] exe_rs_data_div;
    logic [REG_FILE_DATA_WIDTH-1:0] exe_rt_data_div;
    logic [REG_FILE_DATA_WIDTH-1:0] exe_rs_data_mul;
    logic [REG_FILE_DATA_WIDTH-1:0] exe_rt_data_mul;

    PRF #(
        .REG_FILE_DATA_WIDTH     (REG_FILE_DATA_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH)
    ) dut (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .rt_sb_phy_addr        (rt_sb_phy_addr),
        .rt_sb_data            (rt_sb_data),
        .cdb_rd_phy_addr       (cdb_rd_phy_addr),
        .cdb_rd_data           (cdb_rd_data),
        .cdb_reg_write         (cdb_reg_write),
        .issue_rs_phy_addr_alu (issue_rs_phy_addr_alu),
        .issue_rt_phy_addr_alu (issue_rt_phy_addr_alu),
        .issue_rs_phy_addr_div (issue_rs_phy_addr_div),
        .issue_rt_phy_addr_div (issue_rt_phy_addr_div),
        .issue_rs_phy_addr_mul (issue_rs_phy_addr_mul),
        .issue_rt_phy_addr_mul (issue_rt_phy_addr_mul),
        .issue_rs_phy_addr_lsq (issue_rs_phy_addr_lsq),
        .issue_rs_data_lsq     (issue_rs_data_lsq),
        .exe_rs_data_alu       (exe_rs_data_alu),
        .exe_rt_data_alu       (exe_rt_data_alu),
        .exe_rs_data_div       (exe_rs_data_div),
        .exe_rt_data_div       (exe_rt_data_div),
        .exe_rs_data_mul       (exe_rs_data_mul),
        .exe_rt_data_mul       (exe_rt_data_mul)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    int pass_cnt = 0;
    int fail_cnt = 0;

    task automatic check_bit(
        input string tag,
        input logic  actual,
        input logic  expected
    );
        if (actual !== expected) begin
            $error("[FAIL] %s: got %0b, want %0b @ %0t",
                   tag, actual, expected, $time);
            fail_cnt++;
        end else begin
            pass_cnt++;
        end
    endtask

    task automatic check_val(
        input string       tag,
        input logic [63:0] actual,
        input logic [63:0] expected
    );
        if (actual !== expected) begin
            $error("[FAIL] %s: got 0x%0h, want 0x%0h @ %0t",
                   tag, actual, expected, $time);
            fail_cnt++;
        end else begin
            pass_cnt++;
        end
    endtask

    task automatic clear_inputs();
        rt_sb_phy_addr        = '0;
        cdb_rd_phy_addr       = '0;
        cdb_rd_data           = '0;
        cdb_reg_write         = 1'b0;
        issue_rs_phy_addr_alu = '0;
        issue_rt_phy_addr_alu = '0;
        issue_rs_phy_addr_div = '0;
        issue_rt_phy_addr_div = '0;
        issue_rs_phy_addr_mul = '0;
        issue_rt_phy_addr_mul = '0;
        issue_rs_phy_addr_lsq = '0;
    endtask

    task automatic drive_read_addrs(
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] alu_rs,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] alu_rt,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] div_rs,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] div_rt,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] mul_rs,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] mul_rt,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] lsq_rs,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] sb_rt
    );
        issue_rs_phy_addr_alu = alu_rs;
        issue_rt_phy_addr_alu = alu_rt;
        issue_rs_phy_addr_div = div_rs;
        issue_rt_phy_addr_div = div_rt;
        issue_rs_phy_addr_mul = mul_rs;
        issue_rt_phy_addr_mul = mul_rt;
        issue_rs_phy_addr_lsq = lsq_rs;
        rt_sb_phy_addr        = sb_rt;
    endtask

    task automatic expect_all_reads(
        input string                               tag,
        input logic [REG_FILE_DATA_WIDTH-1:0]      alu_rs_v,
        input logic [REG_FILE_DATA_WIDTH-1:0]      alu_rt_v,
        input logic [REG_FILE_DATA_WIDTH-1:0]      div_rs_v,
        input logic [REG_FILE_DATA_WIDTH-1:0]      div_rt_v,
        input logic [REG_FILE_DATA_WIDTH-1:0]      mul_rs_v,
        input logic [REG_FILE_DATA_WIDTH-1:0]      mul_rt_v,
        input logic [REG_FILE_DATA_WIDTH-1:0]      lsq_rs_v,
        input logic [REG_FILE_DATA_WIDTH-1:0]      sb_rt_v
    );
        #1;
        check_val({tag, " alu rs"}, exe_rs_data_alu, alu_rs_v);
        check_val({tag, " alu rt"}, exe_rt_data_alu, alu_rt_v);
        check_val({tag, " div rs"}, exe_rs_data_div, div_rs_v);
        check_val({tag, " div rt"}, exe_rt_data_div, div_rt_v);
        check_val({tag, " mul rs"}, exe_rs_data_mul, mul_rs_v);
        check_val({tag, " mul rt"}, exe_rt_data_mul, mul_rt_v);
        check_val({tag, " lsq rs"}, issue_rs_data_lsq, lsq_rs_v);
        check_val({tag, " sb rt"},  rt_sb_data, sb_rt_v);
    endtask

    task automatic reset_dut();
        rst_n = 1'b0;
        clear_inputs();
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;
    endtask

    task automatic cdb_write(
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] addr,
        input logic [REG_FILE_DATA_WIDTH-1:0]     data
    );
        cdb_rd_phy_addr = addr;
        cdb_rd_data     = data;
        cdb_reg_write   = 1'b1;
        @(posedge clk); #1;
        cdb_reg_write   = 1'b0;
    endtask

    initial begin
        `ifdef FSDB_DUMP
            $fsdbDumpfile("prf.fsdb");
            $fsdbDumpvars(0, PRF_tb);
        `else
            $dumpfile("prf.vcd");
            $dumpvars(0, PRF_tb);
        `endif

        $display("=======================================");
        $display("  PRF Testbench Start");
        $display("=======================================");

        $display("\n[Test 1] Reset: all read ports return zero");
        reset_dut();
        drive_read_addrs(7'd1, 7'd2, 7'd3, 7'd4, 7'd5, 7'd6, 7'd7, 7'd8);
        expect_all_reads("reset", '0, '0, '0, '0, '0, '0, '0, '0);

        $display("\n[Test 2] CDB write visible on following cycle (array read)");
        cdb_write(7'd10, 64'h0000_0000_AA55_AA55);
        drive_read_addrs(7'd10, 7'd0, 7'd0, 7'd0, 7'd0, 7'd0, 7'd0, 7'd0);
        expect_all_reads("post-write alu rs", 64'h0000_0000_AA55_AA55, '0, '0, '0, '0, '0, '0, '0);

        $display("\n[Test 3] Same-cycle CDB bypass on every read port");
        cdb_write(7'd20, 64'h1111_1111_1111_1111);
        drive_read_addrs(7'd20, 7'd20, 7'd20, 7'd20, 7'd20, 7'd20, 7'd20, 7'd20);
        cdb_rd_phy_addr = 7'd20;
        cdb_rd_data     = 64'h2222_2222_2222_2222;
        cdb_reg_write   = 1'b1;
        expect_all_reads("bypass all ports", 64'h2222_2222_2222_2222,
                         64'h2222_2222_2222_2222, 64'h2222_2222_2222_2222,
                         64'h2222_2222_2222_2222, 64'h2222_2222_2222_2222,
                         64'h2222_2222_2222_2222, 64'h2222_2222_2222_2222,
                         64'h2222_2222_2222_2222);
        @(posedge clk); #1;
        cdb_reg_write = 1'b0;

        $display("\n[Test 4] Independent multi-port reads after separate writes");
        reset_dut();
        cdb_write(7'd1, 64'h0000_0000_0000_0001);
        cdb_write(7'd2, 64'h0000_0000_0000_0002);
        cdb_write(7'd3, 64'h0000_0000_0000_0003);
        cdb_write(7'd4, 64'h0000_0000_0000_0004);
        cdb_write(7'd5, 64'h0000_0000_0000_0005);
        cdb_write(7'd6, 64'h0000_0000_0000_0006);
        cdb_write(7'd7, 64'h0000_0000_0000_0007);
        cdb_write(7'd8, 64'h0000_0000_0000_0008);
        drive_read_addrs(7'd1, 7'd2, 7'd3, 7'd4, 7'd5, 7'd6, 7'd7, 7'd8);
        expect_all_reads("independent ports", 64'd1, 64'd2, 64'd3, 64'd4,
                         64'd5, 64'd6, 64'd7, 64'd8);

        $display("\n[Test 5] cdb_reg_write=0 does not update array");
        cdb_write(7'd9, 64'h9999_9999_9999_9999);
        cdb_rd_phy_addr = 7'd9;
        cdb_rd_data     = 64'hBAD0_BAD0_BAD0_BAD0;
        cdb_reg_write   = 1'b0;
        @(posedge clk); #1;
        drive_read_addrs(7'd9, 7'd0, 7'd0, 7'd0, 7'd0, 7'd0, 7'd0, 7'd0);
        expect_all_reads("no spurious write", 64'h9999_9999_9999_9999,
                         '0, '0, '0, '0, '0, '0, '0);

        $display("\n[Test 6] Bypass only when read addr matches CDB write addr");
        cdb_write(7'd30, 64'h0030_0000_0000_0000);
        drive_read_addrs(7'd30, 7'd31, 7'd30, 7'd31, 7'd30, 7'd31, 7'd30, 7'd31);
        cdb_rd_phy_addr = 7'd30;
        cdb_rd_data     = 64'h00FF_0000_0000_0000;
        cdb_reg_write   = 1'b1;
        expect_all_reads("selective bypass", 64'h00FF_0000_0000_0000, 64'h0030_0000_0000_0000,
                         64'h00FF_0000_0000_0000, 64'h0030_0000_0000_0000,
                         64'h00FF_0000_0000_0000, 64'h0030_0000_0000_0000,
                         64'h00FF_0000_0000_0000, 64'h0030_0000_0000_0000);
        @(posedge clk); #1;
        cdb_reg_write = 1'b0;

        $display("\n[Test 7] Overwrite same register across cycles");
        cdb_write(7'd40, 64'h0000_0000_0000_0040);
        cdb_write(7'd40, 64'h0000_0000_0000_8040);
        drive_read_addrs(7'd40, 7'd0, 7'd0, 7'd0, 7'd0, 7'd0, 7'd0, 7'd0);
        expect_all_reads("latest write wins", 64'h0000_0000_0000_8040,
                         '0, '0, '0, '0, '0, '0, '0);

        $display("\n[Test 8] Read unrelated addr during bypass does not forward");
        cdb_write(7'd50, 64'h0000_0000_0000_0050);
        drive_read_addrs(7'd51, 7'd0, 7'd0, 7'd0, 7'd0, 7'd0, 7'd0, 7'd0);
        cdb_rd_phy_addr = 7'd52;
        cdb_rd_data     = 64'h0000_0000_0000_00EE;
        cdb_reg_write   = 1'b1;
        expect_all_reads("no false bypass", '0, '0, '0, '0, '0, '0, '0, '0);
        @(posedge clk); #1;
        cdb_reg_write = 1'b0;

        $display("\n[Test 9] SB and LSQ ports after targeted writes");
        reset_dut();
        cdb_write(7'd60, 64'h0000_0000_0000_0060);
        cdb_write(7'd61, 64'h0000_0000_0000_0061);
        drive_read_addrs(7'd0, 7'd0, 7'd0, 7'd0, 7'd0, 7'd0, 7'd61, 7'd60);
        expect_all_reads("lsq and sb", '0, '0, '0, '0, '0, '0,
                         64'h0000_0000_0000_0061, 64'h0000_0000_0000_0060);

        $display("\n[Test 10] Wide data pattern on DIV/MUL ports");
        cdb_write(7'd70, 64'hDEAD_BEEF_CAFE_BABE);
        cdb_write(7'd71, 64'h0123_4567_89AB_CDEF);
        drive_read_addrs(7'd0, 7'd0, 7'd70, 7'd71, 7'd70, 7'd71, 7'd0, 7'd0);
        expect_all_reads("wide pattern", '0, '0,
                         64'hDEAD_BEEF_CAFE_BABE, 64'h0123_4567_89AB_CDEF,
                         64'hDEAD_BEEF_CAFE_BABE, 64'h0123_4567_89AB_CDEF,
                         '0, '0);

        $display("\n=======================================");
        $display("  PRF Done: %0d passed, %0d failed", pass_cnt, fail_cnt);
        $display("=======================================");

        if (fail_cnt == 0) begin
            $display("[PASS] PRF_tb completed successfully");
        end else begin
            $fatal(1, "[FAIL] PRF_tb found %0d failure(s)", fail_cnt);
        end
        $finish;
    end

    initial begin
        #200_000;
        $error("TIMEOUT");
        $finish;
    end

endmodule
/* verilator lint_on WIDTH */
/* verilator lint_on BLKSEQ */
// verilog_lint: waive-stop explicit-parameter-storage-type
