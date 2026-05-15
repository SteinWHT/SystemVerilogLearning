// Disable width mismatch warnings from some simulators on unsized task arguments.
/* verilator lint_off WIDTH */
// verilog_lint: waive-start explicit-parameter-storage-type
/* verilator lint_off BLKSEQ */
`timescale 1ns/1ps

module INTQ_tb;

    parameter int unsigned INT_QUEUE_DEPTH        = 4;
    parameter int unsigned INSTR_WIDTH            = 32;
    parameter int unsigned ROB_INDEX_WIDTH        = 5;
    parameter int unsigned ARCH_REG_WIDTH         = 5;
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7;
    parameter int unsigned DMEM_WIDTH             = 32;
    parameter int unsigned BPB_PC_BITS            = 3;

    logic clk;
    logic rst_n;

    // CDB interface
    logic                               cdb_flush;
    logic [ROB_INDEX_WIDTH-1:0]         rob_top_ptr;
    logic [ROB_INDEX_WIDTH-1:0]         cdb_rob_depth;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] cdb_rd_phy_addr;
    logic                               cdb_phy_reg_write;

    // Forwarding logic interface
    logic [PHY_REGISTER_FILE_WIDTH-1:0] mul_rd_phy_addr;
    logic                               mul_exe_ready;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] div_rd_phy_addr;
    logic                               div_exe_ready;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] ls_buf_rd_phy_addr;
    logic                               ls_buf_buf_rd_write;

    // ALU interface
    logic [ROB_INDEX_WIDTH-1:0]         iss_rob_tag_alu;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rs_phy_addr_alu;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rt_phy_addr_alu;
    logic [2:0]                         iss_opcode_alu;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rd_phy_addr_alu;
    logic                               iss_rw_alu;
    logic [15:0]                        iss_imm16_alu;
    logic                               iss_branch_prediction_alu;
    logic                               iss_branch_alu;
    logic                               iss_jr_inst_alu;
    logic                               iss_jr31_inst_alu;
    logic                               iss_jal_inst_alu;
    logic [BPB_PC_BITS-1:0]             iss_branch_pc_bits_alu;
    logic [DMEM_WIDTH-1:0]              iss_branch_other_addr_alu;

    // ISSUEUNIT interface
    logic                               issue_int_en;
    logic                               issue_int_rdy;
    logic                               issue_int;

    // Dispatch interface
    logic                               dis_int_en;
    logic                               dis_reg_write;
    logic                               dis_rs_data_ready;
    logic                               dis_rt_data_ready;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rs_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_rt_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_new_rd_phy_addr;
    logic [ROB_INDEX_WIDTH-1:0]         dis_rob_tag;
    logic [2:0]                         dis_opcode;
    logic [15:0]                        dis_imm16;
    logic [DMEM_WIDTH-1:0]              dis_branch_other_addr;
    logic                               dis_branch_prediction;
    logic                               dis_branch;
    logic [BPB_PC_BITS-1:0]             dis_branch_pc_bits;
    logic                               dis_jr_inst;
    logic                               dis_jal_inst;
    logic                               dis_jr31_inst;

    // ISSUEQ interface
    logic                               iss_intq_full;
    logic                               iss_intq_two_or_more_vacant;

    INTQ #(
        .INT_QUEUE_DEPTH        (INT_QUEUE_DEPTH),
        .INSTR_WIDTH            (INSTR_WIDTH),
        .ROB_INDEX_WIDTH        (ROB_INDEX_WIDTH),
        .ARCH_REG_WIDTH         (ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .DMEM_WIDTH             (DMEM_WIDTH),
        .BPB_PC_BITS            (BPB_PC_BITS)
    ) dut (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .cdb_flush                 (cdb_flush),
        .rob_top_ptr               (rob_top_ptr),
        .cdb_rob_depth             (cdb_rob_depth),
        .cdb_rd_phy_addr           (cdb_rd_phy_addr),
        .cdb_phy_reg_write         (cdb_phy_reg_write),
        .mul_rd_phy_addr           (mul_rd_phy_addr),
        .mul_exe_ready             (mul_exe_ready),
        .div_rd_phy_addr           (div_rd_phy_addr),
        .div_exe_ready             (div_exe_ready),
        .ls_buf_rd_phy_addr        (ls_buf_rd_phy_addr),
        .ls_buf_buf_rd_write       (ls_buf_buf_rd_write),
        .iss_rob_tag_alu           (iss_rob_tag_alu),
        .iss_rs_phy_addr_alu       (iss_rs_phy_addr_alu),
        .iss_rt_phy_addr_alu       (iss_rt_phy_addr_alu),
        .iss_opcode_alu            (iss_opcode_alu),
        .iss_rd_phy_addr_alu       (iss_rd_phy_addr_alu),
        .iss_rw_alu                (iss_rw_alu),
        .iss_imm16_alu             (iss_imm16_alu),
        .iss_branch_prediction_alu (iss_branch_prediction_alu),
        .iss_branch_alu            (iss_branch_alu),
        .iss_jr_inst_alu           (iss_jr_inst_alu),
        .iss_jr31_inst_alu         (iss_jr31_inst_alu),
        .iss_jal_inst_alu          (iss_jal_inst_alu),
        .iss_branch_pc_bits_alu    (iss_branch_pc_bits_alu),
        .iss_branch_other_addr_alu (iss_branch_other_addr_alu),
        .issue_int_en              (issue_int_en),
        .issue_int_rdy             (issue_int_rdy),
        .issue_int                 (issue_int),
        .dis_int_en                (dis_int_en),
        .dis_reg_write             (dis_reg_write),
        .dis_rs_data_ready         (dis_rs_data_ready),
        .dis_rt_data_ready         (dis_rt_data_ready),
        .dis_rs_phy_addr           (dis_rs_phy_addr),
        .dis_rt_phy_addr           (dis_rt_phy_addr),
        .dis_new_rd_phy_addr       (dis_new_rd_phy_addr),
        .dis_rob_tag               (dis_rob_tag),
        .dis_opcode                (dis_opcode),
        .dis_imm16                 (dis_imm16),
        .dis_branch_other_addr     (dis_branch_other_addr),
        .dis_branch_prediction     (dis_branch_prediction),
        .dis_branch                (dis_branch),
        .dis_branch_pc_bits        (dis_branch_pc_bits),
        .dis_jr_inst               (dis_jr_inst),
        .dis_jal_inst              (dis_jal_inst),
        .dis_jr31_inst             (dis_jr31_inst),
        .iss_intq_full             (iss_intq_full),
        .iss_intq_two_or_more_vacant(iss_intq_two_or_more_vacant)
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
        mul_rd_phy_addr      = '0;
        mul_exe_ready        = 1'b0;
        div_rd_phy_addr      = '0;
        div_exe_ready        = 1'b0;
        ls_buf_rd_phy_addr   = '0;
        ls_buf_buf_rd_write  = 1'b0;
        issue_int_en         = 1'b0;
        dis_int_en           = 1'b0;
        dis_reg_write        = 1'b0;
        dis_rs_data_ready    = 1'b0;
        dis_rt_data_ready    = 1'b0;
        dis_rs_phy_addr      = '0;
        dis_rt_phy_addr      = '0;
        dis_new_rd_phy_addr  = '0;
        dis_rob_tag          = '0;
        dis_opcode           = '0;
        dis_imm16            = '0;
        dis_branch_other_addr = '0;
        dis_branch_prediction = 1'b0;
        dis_branch           = 1'b0;
        dis_branch_pc_bits   = '0;
        dis_jr_inst          = 1'b0;
        dis_jal_inst         = 1'b0;
        dis_jr31_inst        = 1'b0;
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
        input logic                               rw,
        input logic [15:0]                        imm,
        input logic                               branch,
        input logic                               br_pred,
        input logic                               jr,
        input logic                               jal,
        input logic                               jr31,
        input logic [BPB_PC_BITS-1:0]             br_pc,
        input logic [DMEM_WIDTH-1:0]              br_addr
    );
        dis_int_en            = 1'b1;
        dis_rob_tag           = rob_tag;
        dis_rs_phy_addr       = rs;
        dis_rs_data_ready     = rs_rdy;
        dis_rt_phy_addr       = rt;
        dis_rt_data_ready     = rt_rdy;
        dis_opcode            = opcode;
        dis_new_rd_phy_addr   = rd;
        dis_reg_write         = rw;
        dis_imm16             = imm;
        dis_branch            = branch;
        dis_branch_prediction = br_pred;
        dis_jr_inst           = jr;
        dis_jal_inst          = jal;
        dis_jr31_inst         = jr31;
        dis_branch_pc_bits    = br_pc;
        dis_branch_other_addr = br_addr;
    endtask

    task automatic dispatch_entry(
        input logic [ROB_INDEX_WIDTH-1:0]         rob_tag,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rs,
        input logic                               rs_rdy,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rt,
        input logic                               rt_rdy,
        input logic [2:0]                         opcode,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd,
        input logic                               rw,
        input logic [15:0]                        imm,
        input logic                               branch,
        input logic                               br_pred,
        input logic                               jr,
        input logic                               jal,
        input logic                               jr31,
        input logic [BPB_PC_BITS-1:0]             br_pc,
        input logic [DMEM_WIDTH-1:0]              br_addr
    );
        drive_dispatch(rob_tag, rs, rs_rdy, rt, rt_rdy, opcode, rd, rw, imm,
                       branch, br_pred, jr, jal, jr31, br_pc, br_addr);
        @(posedge clk); #1;
        dis_int_en = 1'b0;
    endtask

    task automatic expect_idle_outputs(input string tag);
        check_bit({tag, " issue_int_rdy"}, issue_int_rdy, 1'b0);
        check_bit({tag, " issue_int"}, issue_int, 1'b0);
        check_val({tag, " iss_rob_tag_alu"}, iss_rob_tag_alu, '0);
        check_val({tag, " iss_rd_phy_addr_alu"}, iss_rd_phy_addr_alu, '0);
        check_val({tag, " iss_rs_phy_addr_alu"}, iss_rs_phy_addr_alu, '0);
        check_val({tag, " iss_rt_phy_addr_alu"}, iss_rt_phy_addr_alu, '0);
    endtask

    task automatic expect_issue_payload(
        input string                               tag,
        input logic [ROB_INDEX_WIDTH-1:0]         rob_tag,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rs,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rt,
        input logic [2:0]                         opcode,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd,
        input logic                               rw,
        input logic [15:0]                        imm,
        input logic                               branch,
        input logic                               br_pred,
        input logic                               jr,
        input logic                               jal,
        input logic                               jr31,
        input logic [BPB_PC_BITS-1:0]             br_pc,
        input logic [DMEM_WIDTH-1:0]              br_addr
    );
        check_bit({tag, " issue_int_rdy"}, issue_int_rdy, 1'b1);
        check_bit({tag, " issue_int"}, issue_int, 1'b1);
        check_val({tag, " rob tag"}, iss_rob_tag_alu, rob_tag);
        check_val({tag, " rs"}, iss_rs_phy_addr_alu, rs);
        check_val({tag, " rt"}, iss_rt_phy_addr_alu, rt);
        check_val({tag, " opcode"}, iss_opcode_alu, opcode);
        check_val({tag, " rd"}, iss_rd_phy_addr_alu, rd);
        check_bit({tag, " rw"}, iss_rw_alu, rw);
        check_val({tag, " imm"}, iss_imm16_alu, imm);
        check_bit({tag, " branch"}, iss_branch_alu, branch);
        check_bit({tag, " branch prediction"}, iss_branch_prediction_alu, br_pred);
        check_bit({tag, " jr"}, iss_jr_inst_alu, jr);
        check_bit({tag, " jal"}, iss_jal_inst_alu, jal);
        check_bit({tag, " jr31"}, iss_jr31_inst_alu, jr31);
        check_val({tag, " branch pc bits"}, iss_branch_pc_bits_alu, br_pc);
        check_val({tag, " branch other addr"}, iss_branch_other_addr_alu, br_addr);
    endtask

    task automatic issue_and_check(
        input string                               tag,
        input logic [ROB_INDEX_WIDTH-1:0]         rob_tag,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rs,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rt,
        input logic [2:0]                         opcode,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] rd,
        input logic                               rw,
        input logic [15:0]                        imm,
        input logic                               branch,
        input logic                               br_pred,
        input logic                               jr,
        input logic                               jal,
        input logic                               jr31,
        input logic [BPB_PC_BITS-1:0]             br_pc,
        input logic [DMEM_WIDTH-1:0]              br_addr
    );
        issue_int_en = 1'b1;
        #1;
        expect_issue_payload(tag, rob_tag, rs, rt, opcode, rd, rw, imm,
                             branch, br_pred, jr, jal, jr31, br_pc, br_addr);
        @(posedge clk); #1;
        issue_int_en = 1'b0;
    endtask

    initial begin
        `ifdef FSDB_DUMP
            $fsdbDumpfile("intq.fsdb");
            $fsdbDumpvars(0, INTQ_tb);
        `else
            $dumpfile("intq.vcd");
            $dumpvars(0, INTQ_tb);
        `endif

        $display("=======================================");
        $display("  INTQ Testbench Start");
        $display("=======================================");

        $display("\n[Test 1] Reset leaves queue empty and ready for dispatch");
        reset_dut();
        expect_idle_outputs("reset");
        check_bit("not full after reset", iss_intq_full, 1'b0);
        check_bit("two or more vacant after reset", iss_intq_two_or_more_vacant, 1'b1);

        $display("\n[Test 2] Dispatch a ready entry and issue its payload");
        dispatch_entry(5'd3, 7'd11, 1'b1, 7'd12, 1'b1, 3'd5, 7'd20, 1'b1,
                       16'h1234, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0, 3'd6, 32'h0000_0040);
        check_bit("ready entry advertises issue_int_rdy", issue_int_rdy, 1'b1);
        check_bit("ready entry does not issue when disabled", issue_int, 1'b0);
        issue_and_check("ready dispatch issue", 5'd3, 7'd11, 7'd12, 3'd5, 7'd20,
                        1'b1, 16'h1234, 1'b1, 1'b0, 1'b0, 1'b0, 1'b0,
                        3'd6, 32'h0000_0040);
        expect_idle_outputs("after issuing only entry");

        $display("\n[Test 3] Entry waits for both operands, then wakes from forwarding buses");
        dispatch_entry(5'd4, 7'd21, 1'b0, 7'd22, 1'b0, 3'd2, 7'd23, 1'b1,
                       16'h2222, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 3'd0, 32'h0);
        expect_idle_outputs("unready after dispatch");

        mul_rd_phy_addr = 7'd21;
        mul_exe_ready   = 1'b1;
        @(posedge clk); #1;
        mul_exe_ready   = 1'b0;
        expect_idle_outputs("only rs ready");

        div_rd_phy_addr = 7'd22;
        div_exe_ready   = 1'b1;
        @(posedge clk); #1;
        div_exe_ready   = 1'b0;
        issue_and_check("forwarded operands issue", 5'd4, 7'd21, 7'd22, 3'd2, 7'd23,
                        1'b1, 16'h2222, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
                        3'd0, 32'h0);

        $display("\n[Test 4] Dispatch-time wakeup catches same-cycle CDB and LS forwarding");
        cdb_rd_phy_addr     = 7'd31;
        cdb_phy_reg_write   = 1'b1;
        ls_buf_rd_phy_addr  = 7'd32;
        ls_buf_buf_rd_write = 1'b1;
        dispatch_entry(5'd5, 7'd31, 1'b0, 7'd32, 1'b0, 3'd1, 7'd33, 1'b0,
                       16'h3333, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 3'd0, 32'h0);
        cdb_phy_reg_write   = 1'b0;
        ls_buf_buf_rd_write = 1'b0;
        issue_and_check("dispatch-time wakeup issue", 5'd5, 7'd31, 7'd32, 3'd1, 7'd33,
                        1'b0, 16'h3333, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
                        3'd0, 32'h0);

        $display("\n[Test 5] Full and two-or-more-vacant flags track occupancy");
        dispatch_entry(5'd8,  7'd1, 1'b1, 7'd2, 1'b1, 3'd0, 7'd10, 1'b1,
                       16'h0008, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 3'd0, 32'h0);
        dispatch_entry(5'd9,  7'd3, 1'b1, 7'd4, 1'b1, 3'd0, 7'd11, 1'b1,
                       16'h0009, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 3'd0, 32'h0);
        check_bit("two entries vacant after two dispatches", iss_intq_two_or_more_vacant, 1'b1);
        dispatch_entry(5'd10, 7'd5, 1'b1, 7'd6, 1'b1, 3'd0, 7'd12, 1'b1,
                       16'h000a, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 3'd0, 32'h0);
        check_bit("only one entry vacant after three dispatches", iss_intq_two_or_more_vacant, 1'b0);
        dispatch_entry(5'd11, 7'd7, 1'b1, 7'd8, 1'b1, 3'd0, 7'd13, 1'b1,
                       16'h000b, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 3'd0, 32'h0);
        check_bit("full after four dispatches", iss_intq_full, 1'b1);
        check_bit("not two-or-more-vacant when full", iss_intq_two_or_more_vacant, 1'b0);

        issue_and_check("issue highest-index full entry", 5'd11, 7'd7, 7'd8, 3'd0, 7'd13,
                        1'b1, 16'h000b, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
                        3'd0, 32'h0);
        check_bit("not full after one issue", iss_intq_full, 1'b0);
        check_bit("still fewer than two vacant after one issue", iss_intq_two_or_more_vacant, 1'b0);

        issue_and_check("issue next highest-index full entry", 5'd10, 7'd5, 7'd6, 3'd0, 7'd12,
                        1'b1, 16'h000a, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
                        3'd0, 32'h0);
        check_bit("two vacant after two issues", iss_intq_two_or_more_vacant, 1'b1);

        issue_and_check("drain next lower-index entry", 5'd9, 7'd3, 7'd4, 3'd0, 7'd11,
                        1'b1, 16'h0009, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
                        3'd0, 32'h0);
        issue_and_check("drain lowest-index entry", 5'd8, 7'd1, 7'd2, 3'd0, 7'd10,
                        1'b1, 16'h0008, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
                        3'd0, 32'h0);
        expect_idle_outputs("after full flag drain");

        $display("\n[Test 6] Flush suppresses issue/dispatch and removes younger entries");
        dispatch_entry(5'd2, 7'd41, 1'b1, 7'd42, 1'b1, 3'd3, 7'd43, 1'b1,
                       16'h0002, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 3'd0, 32'h0);
        dispatch_entry(5'd4, 7'd44, 1'b1, 7'd45, 1'b1, 3'd4, 7'd46, 1'b1,
                       16'h0004, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 3'd0, 32'h0);
        dispatch_entry(5'd7, 7'd47, 1'b1, 7'd48, 1'b1, 3'd5, 7'd49, 1'b1,
                       16'h0007, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 3'd0, 32'h0);

        issue_int_en  = 1'b1;
        cdb_flush     = 1'b1;
        rob_top_ptr   = 5'd0;
        cdb_rob_depth = 5'd4;
        drive_dispatch(5'd9, 7'd50, 1'b1, 7'd51, 1'b1, 3'd6, 7'd52, 1'b1,
                       16'h0009, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0, 3'd0, 32'h0);
        #1;
        check_bit("flush suppresses ready", issue_int_rdy, 1'b0);
        check_bit("flush suppresses issue", issue_int, 1'b0);
        @(posedge clk); #1;
        cdb_flush    = 1'b0;
        issue_int_en = 1'b0;
        dis_int_en   = 1'b0;

        issue_and_check("flush keeps branch-age entry", 5'd4, 7'd44, 7'd45, 3'd4, 7'd46,
                        1'b1, 16'h0004, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
                        3'd0, 32'h0);
        issue_and_check("flush keeps older entry", 5'd2, 7'd41, 7'd42, 3'd3, 7'd43,
                        1'b1, 16'h0002, 1'b0, 1'b0, 1'b0, 1'b0, 1'b0,
                        3'd0, 32'h0);
        expect_idle_outputs("flushed younger and suppressed dispatch");

        $display("\n=======================================");
        $display("  INTQ Testbench Done: %0d passed, %0d failed", pass_cnt, fail_cnt);
        $display("=======================================");

        if (fail_cnt == 0) begin
            $display("[PASS] INTQ_tb completed successfully");
        end else begin
            $fatal(1, "[FAIL] INTQ_tb found %0d failure(s)", fail_cnt);
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
