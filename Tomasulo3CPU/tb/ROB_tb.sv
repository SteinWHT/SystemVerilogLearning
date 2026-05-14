// Disable width mismatch warnings from some simulators on unsized task arguments.
/* verilator lint_off WIDTH */
// verilog_lint: waive-start explicit-parameter-storage-type
/* verilator lint_off BLKSEQ */
`timescale 1ns/1ps

module ROB_tb;

    parameter int unsigned ROB_DEPTH               = 4;
    parameter int unsigned ROB_INDEX_WIDTH         = $clog2(ROB_DEPTH);
    parameter int unsigned DMEM_WIDTH              = 32;
    parameter int unsigned DMEM_DEPTH              = 16;
    parameter int unsigned ARCH_REG_COUNT          = 16;
    parameter int unsigned ARCH_REG_WIDTH          = $clog2(ARCH_REG_COUNT);
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 6;

    logic                                    clk;
    logic                                    rst_n;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]      dis_sw_rt_phy_addr;
    logic                                    dis_inst_sw;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]      dis_pre_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]      dis_new_phy_addr;
    logic                                    dis_inst_valid;
    logic [ARCH_REG_WIDTH-1:0]               dis_rob_rd_arch_addr;
    logic                                    dis_reg_write;
    logic [ROB_INDEX_WIDTH-1:0]              rob_bottom_ptr;
    logic                                    rob_full;
    logic                                    rob_two_or_more_vacant;
    logic                                    cdb_valid;
    logic [ROB_INDEX_WIDTH-1:0]              cdb_rob_tag;
    logic [DMEM_DEPTH-1:0]                   cdb_sw_addr;
    logic [DMEM_WIDTH-1:0]                   cdb_sw_data;
    logic                                    cdb_branch_mispredict;
    logic                                    sb_full;
    logic [DMEM_DEPTH-1:0]                   rob_sw_addr;
    logic [DMEM_WIDTH-1:0]                   rob_sw_data;
    logic                                    rob_commit_mem_write;
    logic [ROB_INDEX_WIDTH-1:0]              rob_top_ptr;
    logic                                    rob_commit;
    logic [ARCH_REG_WIDTH-1:0]               rob_commit_rd_arch_addr;
    logic                                    rob_reg_write;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]      rob_commit_curr_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]      rob_commit_pre_phy_addr;

    ROB #(
        .ROB_DEPTH              (ROB_DEPTH),
        .ROB_INDEX_WIDTH        (ROB_INDEX_WIDTH),
        .DMEM_WIDTH             (DMEM_WIDTH),
        .DMEM_DEPTH             (DMEM_DEPTH),
        .ARCH_REG_COUNT         (ARCH_REG_COUNT),
        .ARCH_REG_WIDTH         (ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH)
    ) dut (
        .clk                    (clk),
        .rst_n                  (rst_n),
        .dis_sw_rt_phy_addr     (dis_sw_rt_phy_addr),
        .dis_inst_sw            (dis_inst_sw),
        .dis_pre_phy_addr       (dis_pre_phy_addr),
        .dis_new_phy_addr       (dis_new_phy_addr),
        .dis_inst_valid         (dis_inst_valid),
        .dis_rob_rd_arch_addr   (dis_rob_rd_arch_addr),
        .dis_reg_write          (dis_reg_write),
        .rob_bottom_ptr         (rob_bottom_ptr),
        .rob_full               (rob_full),
        .rob_two_or_more_vacant (rob_two_or_more_vacant),
        .cdb_valid              (cdb_valid),
        .cdb_rob_tag            (cdb_rob_tag),
        .cdb_sw_addr            (cdb_sw_addr),
        .cdb_sw_data            (cdb_sw_data),
        .cdb_branch_mispredict  (cdb_branch_mispredict),
        .sb_full                (sb_full),
        .rob_sw_addr            (rob_sw_addr),
        .rob_sw_data            (rob_sw_data),
        .rob_commit_mem_write   (rob_commit_mem_write),
        .rob_top_ptr            (rob_top_ptr),
        .rob_commit             (rob_commit),
        .rob_commit_rd_arch_addr(rob_commit_rd_arch_addr),
        .rob_reg_write          (rob_reg_write),
        .rob_commit_curr_phy_addr(rob_commit_curr_phy_addr),
        .rob_commit_pre_phy_addr(rob_commit_pre_phy_addr)
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

    task automatic check_rob_ptr(
        input string                        tag,
        input logic [ROB_INDEX_WIDTH-1:0]   actual,
        input logic [ROB_INDEX_WIDTH-1:0]   expected
    );
        if (actual !== expected) begin
            $error("[FAIL] %s: got 0x%0h, want 0x%0h @ %0t",
                   tag, actual, expected, $time);
            fail_cnt++;
        end else begin
            pass_cnt++;
        end
    endtask

    task automatic check_arch(
        input string                         tag,
        input logic [ARCH_REG_WIDTH-1:0]     actual,
        input logic [ARCH_REG_WIDTH-1:0]     expected
    );
        if (actual !== expected) begin
            $error("[FAIL] %s: got 0x%0h, want 0x%0h @ %0t",
                   tag, actual, expected, $time);
            fail_cnt++;
        end else begin
            pass_cnt++;
        end
    endtask

    task automatic check_phy(
        input string                              tag,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] actual,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] expected
    );
        if (actual !== expected) begin
            $error("[FAIL] %s: got 0x%0h, want 0x%0h @ %0t",
                   tag, actual, expected, $time);
            fail_cnt++;
        end else begin
            pass_cnt++;
        end
    endtask

    task automatic check_dmem_addr(
        input string                   tag,
        input logic [DMEM_DEPTH-1:0]   actual,
        input logic [DMEM_DEPTH-1:0]   expected
    );
        if (actual !== expected) begin
            $error("[FAIL] %s: got 0x%0h, want 0x%0h @ %0t",
                   tag, actual, expected, $time);
            fail_cnt++;
        end else begin
            pass_cnt++;
        end
    endtask

    task automatic check_dmem_data(
        input string                   tag,
        input logic [DMEM_WIDTH-1:0]   actual,
        input logic [DMEM_WIDTH-1:0]   expected
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
        dis_sw_rt_phy_addr    = '0;
        dis_inst_sw           = 1'b0;
        dis_pre_phy_addr      = '0;
        dis_new_phy_addr      = '0;
        dis_inst_valid        = 1'b0;
        dis_rob_rd_arch_addr  = '0;
        dis_reg_write         = 1'b0;
        cdb_valid             = 1'b0;
        cdb_rob_tag           = '0;
        cdb_sw_addr           = '0;
        cdb_sw_data           = '0;
        cdb_branch_mispredict = 1'b0;
        sb_full               = 1'b0;
    endtask

    task automatic reset_dut();
        rst_n = 1'b0;
        clear_inputs();
        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;
    endtask

    task automatic dispatch_reg(
        input logic [ARCH_REG_WIDTH-1:0]          arch_addr,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] curr_phy,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] prev_phy,
        input logic                               reg_write
    );
        dis_inst_sw           = 1'b0;
        dis_new_phy_addr      = curr_phy;
        dis_pre_phy_addr      = prev_phy;
        dis_rob_rd_arch_addr  = arch_addr;
        dis_reg_write         = reg_write;
        dis_inst_valid        = 1'b1;
        @(posedge clk); #1;
        dis_inst_valid        = 1'b0;
    endtask

    task automatic dispatch_store(input logic [PHY_REGISTER_FILE_WIDTH-1:0] store_data_phy);
        dis_inst_sw        = 1'b1;
        dis_sw_rt_phy_addr = store_data_phy;
        dis_reg_write      = 1'b0;
        dis_inst_valid     = 1'b1;
        @(posedge clk); #1;
        dis_inst_valid     = 1'b0;
        dis_inst_sw        = 1'b0;
    endtask

    task automatic complete_reg(input logic [ROB_INDEX_WIDTH-1:0] tag);
        cdb_rob_tag = tag;
        cdb_valid   = 1'b1;
        @(posedge clk); #1;
        cdb_valid   = 1'b0;
    endtask

    task automatic complete_store(
        input logic [ROB_INDEX_WIDTH-1:0] tag,
        input logic [DMEM_DEPTH-1:0]      addr,
        input logic [DMEM_WIDTH-1:0]      data
    );
        cdb_rob_tag = tag;
        cdb_sw_addr = addr;
        cdb_sw_data = data;
        cdb_valid   = 1'b1;
        @(posedge clk); #1;
        cdb_valid   = 1'b0;
    endtask

    task automatic advance_cycle();
        @(posedge clk); #1;
    endtask

    task automatic expect_commit_reg(
        input string                              tag,
        input logic [ROB_INDEX_WIDTH-1:0]         top_ptr,
        input logic [ARCH_REG_WIDTH-1:0]          arch_addr,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] curr_phy,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] prev_phy,
        input logic                               reg_write
    );
        check_bit({tag, " commit"}, rob_commit, 1'b1);
        check_rob_ptr({tag, " top ptr"}, rob_top_ptr, top_ptr);
        check_arch({tag, " arch"}, rob_commit_rd_arch_addr, arch_addr);
        check_phy({tag, " curr phy"}, rob_commit_curr_phy_addr, curr_phy);
        check_phy({tag, " prev phy"}, rob_commit_pre_phy_addr, prev_phy);
        check_bit({tag, " reg write"}, rob_reg_write, reg_write);
        check_bit({tag, " mem write"}, rob_commit_mem_write, 1'b0);
    endtask

    initial begin
        `ifdef FSDB_DUMP
            $fsdbDumpfile("rob.fsdb");
            $fsdbDumpvars(0, ROB_tb);
        `else
            $dumpfile("rob.vcd");
            $dumpvars(0, ROB_tb);
        `endif

        $display("=======================================");
        $display("  ROB Testbench Start");
        $display("=======================================");

        $display("\n[Test 1] Reset leaves ROB empty and ready for allocation");
        reset_dut();
        check_rob_ptr("bottom pointer after reset", rob_bottom_ptr, '0);
        check_rob_ptr("top pointer after reset", rob_top_ptr, '0);
        check_bit("not full after reset", rob_full, 1'b0);
        check_bit("two or more vacant after reset", rob_two_or_more_vacant, 1'b1);
        check_bit("no commit while empty", rob_commit, 1'b0);

        $display("\n[Test 2] Register instruction dispatches, completes, and commits in order");
        dispatch_reg(ARCH_REG_WIDTH'(3), PHY_REGISTER_FILE_WIDTH'(20),
                     PHY_REGISTER_FILE_WIDTH'(5), 1'b1);
        check_rob_ptr("bottom pointer after first dispatch", rob_bottom_ptr, 2'd1);
        check_bit("incomplete head does not commit", rob_commit, 1'b0);

        complete_reg(2'd0);
        expect_commit_reg("completed first entry", 2'd0, ARCH_REG_WIDTH'(3),
                          PHY_REGISTER_FILE_WIDTH'(20),
                          PHY_REGISTER_FILE_WIDTH'(5), 1'b1);

        advance_cycle();
        check_rob_ptr("top pointer after commit advances", rob_top_ptr, 2'd1);
        check_bit("commit deasserts after entry retires", rob_commit, 1'b0);

        $display("\n[Test 3] Younger completed entry waits for older incomplete entry");
        dispatch_reg(ARCH_REG_WIDTH'(1), PHY_REGISTER_FILE_WIDTH'(21),
                     PHY_REGISTER_FILE_WIDTH'(6), 1'b1);
        dispatch_reg(ARCH_REG_WIDTH'(2), PHY_REGISTER_FILE_WIDTH'(22),
                     PHY_REGISTER_FILE_WIDTH'(7), 1'b1);
        check_rob_ptr("top pointer before out-of-order completion", rob_top_ptr, 2'd1);

        complete_reg(2'd2);
        check_bit("younger complete cannot commit before older", rob_commit, 1'b0);

        complete_reg(2'd1);
        expect_commit_reg("older entry commits first", 2'd1, ARCH_REG_WIDTH'(1),
                          PHY_REGISTER_FILE_WIDTH'(21),
                          PHY_REGISTER_FILE_WIDTH'(6), 1'b1);

        advance_cycle();
        expect_commit_reg("younger entry commits next", 2'd2, ARCH_REG_WIDTH'(2),
                          PHY_REGISTER_FILE_WIDTH'(22),
                          PHY_REGISTER_FILE_WIDTH'(7), 1'b1);

        advance_cycle();
        check_rob_ptr("top pointer after two ordered commits", rob_top_ptr, 2'd3);
        check_bit("ROB idle after ordered commits", rob_commit, 1'b0);

        $display("\n[Test 4] Store commit waits while store buffer is full");
        dispatch_store(PHY_REGISTER_FILE_WIDTH'(31));
        complete_store(2'd3, DMEM_DEPTH'(16'h00a5), DMEM_WIDTH'(32'hcafe_1234));
        sb_full = 1'b1;
        #1;
        check_bit("completed store blocked by full store buffer", rob_commit, 1'b0);
        check_dmem_addr("store address visible at ROB head", rob_sw_addr, DMEM_DEPTH'(16'h00a5));
        check_dmem_data("store data captured from CDB", rob_sw_data, DMEM_WIDTH'(32'hcafe_1234));

        sb_full = 1'b0;
        #1;
        check_bit("completed store commits when store buffer has space", rob_commit, 1'b1);
        check_bit("store commit asserts mem write", rob_commit_mem_write, 1'b1);

        advance_cycle();
        check_rob_ptr("top pointer wraps after store commit", rob_top_ptr, 2'd0);
        check_bit("no commit after store retires", rob_commit, 1'b0);

        $display("\n[Test 5] Full and two-or-more-vacant status track allocations");
        reset_dut();
        dispatch_reg(ARCH_REG_WIDTH'(0), PHY_REGISTER_FILE_WIDTH'(16),
                     PHY_REGISTER_FILE_WIDTH'(0), 1'b1);
        dispatch_reg(ARCH_REG_WIDTH'(1), PHY_REGISTER_FILE_WIDTH'(17),
                     PHY_REGISTER_FILE_WIDTH'(1), 1'b1);
        check_bit("two vacant entries remain after two allocations",
                  rob_two_or_more_vacant, 1'b1);

        dispatch_reg(ARCH_REG_WIDTH'(2), PHY_REGISTER_FILE_WIDTH'(18),
                     PHY_REGISTER_FILE_WIDTH'(2), 1'b1);
        check_bit("one vacant entry is not two-or-more vacant",
                  rob_two_or_more_vacant, 1'b0);

        dispatch_reg(ARCH_REG_WIDTH'(3), PHY_REGISTER_FILE_WIDTH'(19),
                     PHY_REGISTER_FILE_WIDTH'(3), 1'b1);
        check_bit("ROB full after four allocations", rob_full, 1'b1);
        check_rob_ptr("bottom pointer wraps when full", rob_bottom_ptr, 2'd0);

        dispatch_reg(ARCH_REG_WIDTH'(4), PHY_REGISTER_FILE_WIDTH'(20),
                     PHY_REGISTER_FILE_WIDTH'(4), 1'b1);
        check_bit("dispatch is blocked while full", rob_full, 1'b1);
        check_rob_ptr("bottom pointer held while full", rob_bottom_ptr, 2'd0);

        complete_reg(2'd0);
        advance_cycle();
        check_bit("commit creates space", rob_full, 1'b0);
        check_rob_ptr("top pointer advances after freeing one entry", rob_top_ptr, 2'd1);

        $display("\n[Test 6] Branch mispredict flush moves bottom pointer to CDB tag");
        reset_dut();
        dispatch_reg(ARCH_REG_WIDTH'(5), PHY_REGISTER_FILE_WIDTH'(25),
                     PHY_REGISTER_FILE_WIDTH'(9), 1'b1);
        dispatch_reg(ARCH_REG_WIDTH'(6), PHY_REGISTER_FILE_WIDTH'(26),
                     PHY_REGISTER_FILE_WIDTH'(10), 1'b1);
        dispatch_reg(ARCH_REG_WIDTH'(7), PHY_REGISTER_FILE_WIDTH'(27),
                     PHY_REGISTER_FILE_WIDTH'(11), 1'b1);
        check_rob_ptr("bottom before flush", rob_bottom_ptr, 2'd3);

        cdb_rob_tag            = 2'd1;
        cdb_branch_mispredict  = 1'b1;
        advance_cycle();
        cdb_branch_mispredict  = 1'b0;
        check_rob_ptr("bottom after flush to tag 1", rob_bottom_ptr, 2'd1);
        check_bit("ROB no longer full after flush", rob_full, 1'b0);

        dispatch_reg(ARCH_REG_WIDTH'(8), PHY_REGISTER_FILE_WIDTH'(28),
                     PHY_REGISTER_FILE_WIDTH'(12), 1'b1);
        check_rob_ptr("dispatch reuses flushed slot", rob_bottom_ptr, 2'd2);

        $display("\n=======================================");
        $display("  ROB Testbench Done: %0d passed, %0d failed", pass_cnt, fail_cnt);
        $display("=======================================");

        if (fail_cnt == 0) begin
            $display("[PASS] ROB_tb completed successfully");
        end else begin
            $fatal(1, "[FAIL] ROB_tb found %0d failure(s)", fail_cnt);
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
