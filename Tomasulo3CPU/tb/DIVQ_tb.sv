// Disable width mismatch warnings from some simulators on unsized task arguments.
/* verilator lint_off WIDTH */
// verilog_lint: waive-start explicit-parameter-storage-type
/* verilator lint_off BLKSEQ */
`timescale 1ns/1ps

module DIVQ_tb;

    parameter int unsigned DIV_QUEUE_DEPTH         = 4;
    parameter int unsigned INSTR_WIDTH             = 32;
    parameter int unsigned ROB_INDEX_WIDTH         = 5;
    parameter int unsigned ARCH_REG_WIDTH          = 5;
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7;
    parameter int unsigned DMEM_WIDTH              = 32;

    logic clk;
    logic rst_n;

    // CDB interface
    logic                               cdb_flush;
    logic [ROB_INDEX_WIDTH-1:0]         rob_top_ptr;
    logic [ROB_INDEX_WIDTH-1:0]         cdb_rob_depth;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] cdb_rd_phy_addr;
    logic                               cdb_phy_reg_write;

    // Forwarding logic interface
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rd_phy_addr_alu;
    logic                               iss_rd_reg_valid_alu;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] mul_rd_phy_addr;
    logic                               mul_exe_ready;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] div_rd_phy_addr;
    logic                               div_exe_ready;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] ls_buf_rd_phy_addr;
    logic                               ls_buf_buf_rd_write;

    // DIV interface
    logic [ROB_INDEX_WIDTH-1:0]         iss_rob_tag_div;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rs_phy_addr_div;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rt_phy_addr_div;
    logic [2:0]                         iss_opcode_div;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rd_phy_addr_div;
    logic                               iss_rw_div;

    // ISSUEUNIT interface
    logic                               issue_div_en;
    logic                               issue_div_rdy;
    logic                               issue_div;

    // Dispatch interface
    logic                               dis_div_issq_en;
    logic                               dis_reg_write;
    logic                               dis_rs_data_ready;
    logic                               dis_rt_data_ready;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rs_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rt_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_new_rd_phy_addr;
    logic [ROB_INDEX_WIDTH-1:0]         dis_rob_tag;
    logic [2:0]                         dis_opcode;

    // Queue status
    logic                               divq_full;
    logic                               iss_divq_two_or_more_vacant;

    DIVQ #(
        .DIV_QUEUE_DEPTH        (DIV_QUEUE_DEPTH),
        .INSTR_WIDTH            (INSTR_WIDTH),
        .ROB_INDEX_WIDTH        (ROB_INDEX_WIDTH),
        .ARCH_REG_WIDTH         (ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .DMEM_WIDTH             (DMEM_WIDTH)
    ) dut (
        .clk                         (clk),
        .rst_n                       (rst_n),
        .cdb_flush                   (cdb_flush),
        .rob_top_ptr                 (rob_top_ptr),
        .cdb_rob_depth               (cdb_rob_depth),
        .cdb_rd_phy_addr             (cdb_rd_phy_addr),
        .cdb_phy_reg_write           (cdb_phy_reg_write),
        .iss_rd_phy_addr_alu         (iss_rd_phy_addr_alu),
        .iss_rd_reg_valid_alu        (iss_rd_reg_valid_alu),
        .mul_rd_phy_addr             (mul_rd_phy_addr),
        .mul_exe_ready               (mul_exe_ready),
        .div_rd_phy_addr             (div_rd_phy_addr),
        .div_exe_ready               (div_exe_ready),
        .ls_buf_rd_phy_addr          (ls_buf_rd_phy_addr),
        .ls_buf_buf_rd_write         (ls_buf_buf_rd_write),
        .iss_rob_tag_div             (iss_rob_tag_div),
        .iss_rs_phy_addr_div         (iss_rs_phy_addr_div),
        .iss_rt_phy_addr_div         (iss_rt_phy_addr_div),
        .iss_opcode_div              (iss_opcode_div),
        .iss_rd_phy_addr_div         (iss_rd_phy_addr_div),
        .iss_rw_div                  (iss_rw_div),
        .issue_div_en                (issue_div_en),
        .issue_div_rdy               (issue_div_rdy),
        .issue_div                   (issue_div),
        .dis_div_issq_en             (dis_div_issq_en),
        .dis_reg_write               (dis_reg_write),
        .dis_rs_data_ready           (dis_rs_data_ready),
        .dis_rt_data_ready           (dis_rt_data_ready),
        .dis_rs_phy_addr             (dis_rs_phy_addr),
        .dis_rt_phy_addr             (dis_rt_phy_addr),
        .dis_new_rd_phy_addr         (dis_new_rd_phy_addr),
        .dis_rob_tag                 (dis_rob_tag),
        .dis_opcode                  (dis_opcode),
        .divq_full                   (divq_full),
        .iss_divq_two_or_more_vacant (iss_divq_two_or_more_vacant)
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
        cdb_flush            = 1'b0;
        rob_top_ptr          = '0;
        cdb_rob_depth        = '0;
        cdb_rd_phy_addr      = '0;
        cdb_phy_reg_write    = 1'b0;
        iss_rd_phy_addr_alu  = '0;
        iss_rd_reg_valid_alu = 1'b0;
        mul_rd_phy_addr      = '0;
        mul_exe_ready        = 1'b0;
        div_rd_phy_addr      = '0;
        div_exe_ready        = 1'b0;
        ls_buf_rd_phy_addr   = '0;
        ls_buf_buf_rd_write  = 1'b0;
        issue_div_en         = 1'b0;
        dis_div_issq_en      = 1'b0;
        dis_reg_write        = 1'b0;
        dis_rs_data_ready    = 1'b0;
        dis_rt_data_ready    = 1'b0;
        dis_rs_phy_addr      = '0;
        dis_rt_phy_addr      = '0;
        dis_new_rd_phy_addr  = '0;
        dis_rob_tag          = '0;
        dis_opcode           = '0;
    endtask

    task automatic reset_dut();
        rst_n = 1'b0;
        clear_inputs();
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;
    endtask

    task automatic drive_dispatch(
        input logic [ROB_INDEX_WIDTH-1:0]         rob_tag,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rs,
        input logic                               rs_rdy,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rt,
        input logic                               rt_rdy,
        input logic [2:0]                         opcode,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd,
        input logic                               rw
    );
        dis_div_issq_en     = 1'b1;
        dis_rob_tag         = rob_tag;
        dis_rs_phy_addr     = rs;
        dis_rs_data_ready   = rs_rdy;
        dis_rt_phy_addr     = rt;
        dis_rt_data_ready   = rt_rdy;
        dis_opcode          = opcode;
        dis_new_rd_phy_addr = rd;
        dis_reg_write       = rw;
    endtask

    task automatic dispatch_entry(
        input logic [ROB_INDEX_WIDTH-1:0]         rob_tag,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rs,
        input logic                               rs_rdy,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rt,
        input logic                               rt_rdy,
        input logic [2:0]                         opcode,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd,
        input logic                               rw
    );
        drive_dispatch(rob_tag, rs, rs_rdy, rt, rt_rdy, opcode, rd, rw);
        @(posedge clk); #1;
        dis_div_issq_en = 1'b0;
    endtask

    task automatic expect_idle_outputs(input string tag);
        check_bit({tag, " issue_div_rdy"}, issue_div_rdy, 1'b0);
        check_bit({tag, " issue_div"}, issue_div, 1'b0);
        check_val({tag, " iss_rob_tag_div"}, iss_rob_tag_div, '0);
        check_val({tag, " iss_rd_phy_addr_div"}, iss_rd_phy_addr_div, '0);
        check_val({tag, " iss_rs_phy_addr_div"}, iss_rs_phy_addr_div, '0);
        check_val({tag, " iss_rt_phy_addr_div"}, iss_rt_phy_addr_div, '0);
    endtask

    task automatic expect_issue_payload(
        input string                               tag,
        input logic [ROB_INDEX_WIDTH-1:0]         rob_tag,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rs,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rt,
        input logic [2:0]                         opcode,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd,
        input logic                               rw
    );
        check_bit({tag, " issue_div_rdy"}, issue_div_rdy, 1'b1);
        check_bit({tag, " issue_div"}, issue_div, 1'b1);
        check_val({tag, " rob tag"}, iss_rob_tag_div, rob_tag);
        check_val({tag, " rs"}, iss_rs_phy_addr_div, rs);
        check_val({tag, " rt"}, iss_rt_phy_addr_div, rt);
        check_val({tag, " opcode"}, iss_opcode_div, opcode);
        check_val({tag, " rd"}, iss_rd_phy_addr_div, rd);
        check_bit({tag, " rw"}, iss_rw_div, rw);
    endtask

    task automatic issue_and_check(
        input string                               tag,
        input logic [ROB_INDEX_WIDTH-1:0]         rob_tag,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rs,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rt,
        input logic [2:0]                         opcode,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd,
        input logic                               rw
    );
        issue_div_en = 1'b1;
        #1;
        expect_issue_payload(tag, rob_tag, rs, rt, opcode, rd, rw);
        @(posedge clk); #1;
        issue_div_en = 1'b0;
    endtask

    initial begin
        `ifdef FSDB_DUMP
            $fsdbDumpfile("divq.fsdb");
            $fsdbDumpvars(0, DIVQ_tb);
        `else
            $dumpfile("divq.vcd");
            $dumpvars(0, DIVQ_tb);
        `endif

        $display("=======================================");
        $display("  DIVQ Testbench Start");
        $display("=======================================");

        $display("\n[Test 1] Reset leaves queue empty and ready for dispatch");
        reset_dut();
        expect_idle_outputs("reset");
        check_bit("not full after reset", divq_full, 1'b0);
        check_bit("two or more vacant after reset", iss_divq_two_or_more_vacant, 1'b1);

        $display("\n[Test 2] Dispatch a ready entry and issue its payload");
        dispatch_entry(5'd3, 7'd11, 1'b1, 7'd12, 1'b1, 3'd5, 7'd20, 1'b1);
        check_bit("ready entry advertises issue_div_rdy", issue_div_rdy, 1'b1);
        check_bit("ready entry does not issue when disabled", issue_div, 1'b0);
        issue_and_check("ready dispatch issue", 5'd3, 7'd11, 7'd12, 3'd5, 7'd20, 1'b1);
        expect_idle_outputs("after issuing only entry");

        $display("\n[Test 3] Entry waits for both operands, then wakes from forwarding buses");
        dispatch_entry(5'd4, 7'd21, 1'b0, 7'd22, 1'b0, 3'd2, 7'd23, 1'b1);
        expect_idle_outputs("unready after dispatch");

        iss_rd_phy_addr_alu  = 7'd21;
        iss_rd_reg_valid_alu = 1'b1;
        @(posedge clk); #1;
        iss_rd_reg_valid_alu = 1'b0;
        expect_idle_outputs("only rs ready");

        mul_rd_phy_addr = 7'd22;
        mul_exe_ready   = 1'b1;
        @(posedge clk); #1;
        mul_exe_ready   = 1'b0;
        issue_and_check("forwarded operands issue", 5'd4, 7'd21, 7'd22, 3'd2, 7'd23, 1'b1);

        $display("\n[Test 4] Dispatch-time wakeup catches same-cycle CDB and LS forwarding");
        cdb_rd_phy_addr     = 7'd31;
        cdb_phy_reg_write   = 1'b1;
        ls_buf_rd_phy_addr  = 7'd32;
        ls_buf_buf_rd_write = 1'b1;
        dispatch_entry(5'd5, 7'd31, 1'b0, 7'd32, 1'b0, 3'd1, 7'd33, 1'b0);
        cdb_phy_reg_write   = 1'b0;
        ls_buf_buf_rd_write = 1'b0;
        issue_and_check("dispatch-time wakeup issue", 5'd5, 7'd31, 7'd32, 3'd1, 7'd33, 1'b0);

        $display("\n[Test 5] Full and two-or-more-vacant flags track occupancy");
        dispatch_entry(5'd8,  7'd1, 1'b1, 7'd2, 1'b1, 3'd0, 7'd10, 1'b1);
        dispatch_entry(5'd9,  7'd3, 1'b1, 7'd4, 1'b1, 3'd0, 7'd11, 1'b1);
        check_bit("two entries vacant after two dispatches", iss_divq_two_or_more_vacant, 1'b1);
        dispatch_entry(5'd10, 7'd5, 1'b1, 7'd6, 1'b1, 3'd0, 7'd12, 1'b1);
        check_bit("only one entry vacant after three dispatches", iss_divq_two_or_more_vacant, 1'b0);
        dispatch_entry(5'd11, 7'd7, 1'b1, 7'd8, 1'b1, 3'd0, 7'd13, 1'b1);
        check_bit("full after four dispatches", divq_full, 1'b1);
        check_bit("not two-or-more-vacant when full", iss_divq_two_or_more_vacant, 1'b0);

        issue_and_check("issue highest-index full entry", 5'd11, 7'd7, 7'd8, 3'd0, 7'd13, 1'b1);
        check_bit("not full after one issue", divq_full, 1'b0);
        check_bit("still fewer than two vacant after one issue", iss_divq_two_or_more_vacant, 1'b0);

        issue_and_check("issue next highest-index full entry", 5'd10, 7'd5, 7'd6, 3'd0, 7'd12, 1'b1);
        check_bit("two vacant after two issues", iss_divq_two_or_more_vacant, 1'b1);

        issue_and_check("drain next lower-index entry", 5'd9, 7'd3, 7'd4, 3'd0, 7'd11, 1'b1);
        issue_and_check("drain lowest-index entry", 5'd8, 7'd1, 7'd2, 3'd0, 7'd10, 1'b1);
        expect_idle_outputs("after full flag drain");

        $display("\n[Test 6] Flush suppresses issue/dispatch and removes younger entries");
        dispatch_entry(5'd2, 7'd41, 1'b1, 7'd42, 1'b1, 3'd3, 7'd43, 1'b1);
        dispatch_entry(5'd4, 7'd44, 1'b1, 7'd45, 1'b1, 3'd4, 7'd46, 1'b1);
        dispatch_entry(5'd7, 7'd47, 1'b1, 7'd48, 1'b1, 3'd5, 7'd49, 1'b1);

        issue_div_en  = 1'b1;
        cdb_flush     = 1'b1;
        rob_top_ptr   = 5'd0;
        cdb_rob_depth = 5'd4;
        drive_dispatch(5'd9, 7'd50, 1'b1, 7'd51, 1'b1, 3'd6, 7'd52, 1'b1);
        #1;
        check_bit("flush suppresses ready", issue_div_rdy, 1'b0);
        check_bit("flush suppresses issue", issue_div, 1'b0);
        @(posedge clk); #1;
        cdb_flush       = 1'b0;
        issue_div_en    = 1'b0;
        dis_div_issq_en = 1'b0;

        issue_and_check("flush keeps branch-age entry", 5'd4, 7'd44, 7'd45, 3'd4, 7'd46, 1'b1);
        issue_and_check("flush keeps older entry", 5'd2, 7'd41, 7'd42, 3'd3, 7'd43, 1'b1);
        expect_idle_outputs("flushed younger and suppressed dispatch");

        $display("\n=======================================");
        $display("  DIVQ Testbench Done: %0d passed, %0d failed", pass_cnt, fail_cnt);
        $display("=======================================");

        if (fail_cnt == 0) begin
            $display("[PASS] DIVQ_tb completed successfully");
        end else begin
            $fatal(1, "[FAIL] DIVQ_tb found %0d failure(s)", fail_cnt);
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
