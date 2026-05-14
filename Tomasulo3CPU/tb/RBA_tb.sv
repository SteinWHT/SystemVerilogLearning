// Disable width mismatch warnings from some simulators on unsized task arguments.
/* verilator lint_off WIDTH */
// verilog_lint: waive-start explicit-parameter-storage-type
/* verilator lint_off BLKSEQ */
`timescale 1ns/1ps

module RBA_tb;

    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 4;
    parameter int unsigned PHY_REG_COUNT           = 1 << PHY_REGISTER_FILE_WIDTH;

    logic                                      clk;
    logic                                      rst_n;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]        dis_rs_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]        dis_rt_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]        dis_new_rd_phy_addr;
    logic                                      dis_reg_write;
    logic                                      rs_data_ready;
    logic                                      rt_data_ready;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]        rd_phy_addr;
    logic                                      cdb_reg_write;

    RBA #(
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .PHY_REG_COUNT          (PHY_REG_COUNT)
    ) dut (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .dis_rs_phy_addr       (dis_rs_phy_addr),
        .dis_rt_phy_addr       (dis_rt_phy_addr),
        .dis_new_rd_phy_addr   (dis_new_rd_phy_addr),
        .dis_reg_write         (dis_reg_write),
        .rs_data_ready         (rs_data_ready),
        .rt_data_ready         (rt_data_ready),
        .rd_phy_addr           (rd_phy_addr),
        .cdb_reg_write         (cdb_reg_write)
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

    task automatic clear_inputs();
        dis_rs_phy_addr     = '0;
        dis_rt_phy_addr     = '0;
        dis_new_rd_phy_addr = '0;
        dis_reg_write       = 1'b0;
        rd_phy_addr         = '0;
        cdb_reg_write       = 1'b0;
    endtask

    task automatic reset_dut();
        rst_n = 1'b0;
        clear_inputs();
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;
    endtask

    task automatic set_read_addrs(
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rs_addr,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rt_addr
    );
        dis_rs_phy_addr = rs_addr;
        dis_rt_phy_addr = rt_addr;
        #1;
    endtask

    task automatic expect_ready(
        input string tag,
        input logic  rs_expected,
        input logic  rt_expected
    );
        check_bit({tag, " rs"}, rs_data_ready, rs_expected);
        check_bit({tag, " rt"}, rt_data_ready, rt_expected);
    endtask

    task automatic cdb_write(input logic [PHY_REGISTER_FILE_WIDTH-1:0] phy_addr);
        rd_phy_addr   = phy_addr;
        cdb_reg_write = 1'b1;
        @(posedge clk); #1;
        cdb_reg_write = 1'b0;
    endtask

    task automatic dispatch_clear(input logic [PHY_REGISTER_FILE_WIDTH-1:0] phy_addr);
        dis_new_rd_phy_addr = phy_addr;
        dis_reg_write       = 1'b1;
        @(posedge clk); #1;
        dis_reg_write       = 1'b0;
    endtask

    task automatic simultaneous_clear_and_cdb(
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] clear_addr,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] cdb_addr
    );
        dis_new_rd_phy_addr = clear_addr;
        dis_reg_write       = 1'b1;
        rd_phy_addr         = cdb_addr;
        cdb_reg_write       = 1'b1;
        @(posedge clk); #1;
        dis_reg_write       = 1'b0;
        cdb_reg_write       = 1'b0;
    endtask

    initial begin
        `ifdef FSDB_DUMP
            $fsdbDumpfile("rba.fsdb");
            $fsdbDumpvars(0, RBA_tb);
        `else
            $dumpfile("rba.vcd");
            $dumpvars(0, RBA_tb);
        `endif

        $display("=======================================");
        $display("  RBA Testbench Start");
        $display("=======================================");

        $display("\n[Test 1] Reset clears all ready bits");
        reset_dut();
        for (int i = 0; i < PHY_REG_COUNT; i += 3) begin
            set_read_addrs(PHY_REGISTER_FILE_WIDTH'(i),
                           PHY_REGISTER_FILE_WIDTH'((i + 1) % PHY_REG_COUNT));
            expect_ready($sformatf("reset ready[%0d,%0d]", i, (i + 1) % PHY_REG_COUNT),
                         1'b0, 1'b0);
        end

        $display("\n[Test 2] CDB write marks a physical register ready");
        cdb_write(PHY_REGISTER_FILE_WIDTH'(5));
        set_read_addrs(PHY_REGISTER_FILE_WIDTH'(5), PHY_REGISTER_FILE_WIDTH'(6));
        expect_ready("after CDB writes p5", 1'b1, 1'b0);

        cdb_write(PHY_REGISTER_FILE_WIDTH'(9));
        set_read_addrs(PHY_REGISTER_FILE_WIDTH'(5), PHY_REGISTER_FILE_WIDTH'(9));
        expect_ready("two independent ready registers", 1'b1, 1'b1);

        $display("\n[Test 3] Dispatch register write clears the new destination ready bit");
        dispatch_clear(PHY_REGISTER_FILE_WIDTH'(5));
        set_read_addrs(PHY_REGISTER_FILE_WIDTH'(5), PHY_REGISTER_FILE_WIDTH'(9));
        expect_ready("dispatch clears p5 but leaves p9 ready", 1'b0, 1'b1);

        $display("\n[Test 4] Reads are purely address-selected");
        set_read_addrs(PHY_REGISTER_FILE_WIDTH'(9), PHY_REGISTER_FILE_WIDTH'(5));
        expect_ready("swapped source addresses", 1'b1, 1'b0);

        set_read_addrs(PHY_REGISTER_FILE_WIDTH'(9), PHY_REGISTER_FILE_WIDTH'(9));
        expect_ready("same ready physical register on both ports", 1'b1, 1'b1);

        set_read_addrs(PHY_REGISTER_FILE_WIDTH'(5), PHY_REGISTER_FILE_WIDTH'(5));
        expect_ready("same not-ready physical register on both ports", 1'b0, 1'b0);

        $display("\n[Test 5] Same-cycle clear and CDB behavior");
        cdb_write(PHY_REGISTER_FILE_WIDTH'(7));
        simultaneous_clear_and_cdb(PHY_REGISTER_FILE_WIDTH'(7), PHY_REGISTER_FILE_WIDTH'(7));
        set_read_addrs(PHY_REGISTER_FILE_WIDTH'(7), PHY_REGISTER_FILE_WIDTH'(9));
        expect_ready("CDB has priority when same register is cleared and completed",
                     1'b1, 1'b1);

        simultaneous_clear_and_cdb(PHY_REGISTER_FILE_WIDTH'(9), PHY_REGISTER_FILE_WIDTH'(12));
        set_read_addrs(PHY_REGISTER_FILE_WIDTH'(9), PHY_REGISTER_FILE_WIDTH'(12));
        expect_ready("different clear and CDB addresses update independently",
                     1'b0, 1'b1);

        $display("\n=======================================");
        $display("  RBA Testbench Done: %0d passed, %0d failed", pass_cnt, fail_cnt);
        $display("=======================================");

        if (fail_cnt == 0) begin
            $display("[PASS] RBA_tb completed successfully");
        end else begin
            $fatal(1, "[FAIL] RBA_tb found %0d failure(s)", fail_cnt);
        end
        $finish;
    end

    initial begin
        #100_000;
        $error("TIMEOUT");
        $finish;
    end

endmodule
/* verilator lint_on WIDTH */
/* verilator lint_on BLKSEQ */
// verilog_lint: waive-stop explicit-parameter-storage-type
