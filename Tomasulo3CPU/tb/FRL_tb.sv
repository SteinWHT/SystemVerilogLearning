// Disable width mismatch warnings from some simulators on unsized task arguments.
/* verilator lint_off WIDTH */
// verilog_lint: waive-start explicit-parameter-storage-type
/* verilator lint_off BLKSEQ */
`timescale 1ns/1ps

module FRL_tb;

    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7;
    parameter int unsigned ARCH_REG_COUNT          = 32;
    parameter int unsigned FRL_SIZE                = 2**PHY_REGISTER_FILE_WIDTH - ARCH_REG_COUNT;
    parameter int unsigned FRL_PTR_WIDTH           = $clog2(FRL_SIZE);

    logic                                      clk;
    logic                                      rst_n;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]        rob_commit_pre_phy_address;
    logic                                      rob_commit;
    logic                                      rob_commit_reg_write;
    logic [FRL_PTR_WIDTH:0]                    frat_frl_head_ptr;
    logic                                      cdb_flush;
    logic                                      dis_frl_read;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]        frl_read_phy_address;
    logic                                      frl_read_empty;
    logic [FRL_PTR_WIDTH:0]                    frl_head_ptr_to_frat;

    FRL #(
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .ARCH_REG_COUNT         (ARCH_REG_COUNT),
        .FRL_SIZE               (FRL_SIZE),
        .FRL_PTR_WIDTH          (FRL_PTR_WIDTH)
    ) dut (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .rob_commit_pre_phy_address(rob_commit_pre_phy_address),
        .rob_commit                (rob_commit),
        .rob_commit_reg_write      (rob_commit_reg_write),
        .frat_frl_head_ptr         (frat_frl_head_ptr),
        .cdb_flush                 (cdb_flush),
        .dis_frl_read              (dis_frl_read),
        .frl_read_phy_address      (frl_read_phy_address),
        .frl_read_empty            (frl_read_empty),
        .frl_head_ptr_to_frat      (frl_head_ptr_to_frat)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    int pass_cnt = 0;
    int fail_cnt = 0;

    function automatic logic [FRL_PTR_WIDTH:0] ptr_next(
        input logic [FRL_PTR_WIDTH:0] ptr
    );
        if (ptr[FRL_PTR_WIDTH-1:0] == FRL_PTR_WIDTH'(FRL_SIZE - 1)) begin
            ptr_next = {~ptr[FRL_PTR_WIDTH], {FRL_PTR_WIDTH{1'b0}}};
        end else begin
            ptr_next = ptr + 1'b1;
        end
    endfunction

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

    task automatic check_ptr(
        input string                    tag,
        input logic [FRL_PTR_WIDTH:0]   actual,
        input logic [FRL_PTR_WIDTH:0]   expected
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
        input string                               tag,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0]  actual,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0]  expected
    );
        if (actual !== expected) begin
            $error("[FAIL] %s: got 0x%0h, want 0x%0h @ %0t",
                   tag, actual, expected, $time);
            fail_cnt++;
        end else begin
            pass_cnt++;
        end
    endtask

    task automatic reset_dut();
        rst_n                      = 1'b0;
        rob_commit_pre_phy_address = '0;
        rob_commit                 = 1'b0;
        rob_commit_reg_write       = 1'b0;
        frat_frl_head_ptr          = '0;
        cdb_flush                  = 1'b0;
        dis_frl_read               = 1'b0;

        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;
    endtask

    task automatic read_free_reg(output logic [PHY_REGISTER_FILE_WIDTH-1:0] phy_addr);
        dis_frl_read = 1'b1;
        @(posedge clk); #1;
        phy_addr = frl_read_phy_address;
        dis_frl_read = 1'b0;
    endtask

    task automatic commit_free_reg(input logic [PHY_REGISTER_FILE_WIDTH-1:0] phy_addr);
        rob_commit_pre_phy_address = phy_addr;
        rob_commit                 = 1'b1;
        rob_commit_reg_write       = 1'b1;
        @(posedge clk); #1;
        rob_commit                 = 1'b0;
        rob_commit_reg_write       = 1'b0;
    endtask

    task automatic restore_head(input logic [FRL_PTR_WIDTH:0] checkpoint_head);
        frat_frl_head_ptr = checkpoint_head;
        cdb_flush         = 1'b1;
        @(posedge clk); #1;
        cdb_flush         = 1'b0;
    endtask

    logic [PHY_REGISTER_FILE_WIDTH-1:0] phy_addr;
    logic [FRL_PTR_WIDTH:0]             saved_head_ptr;

    initial begin
        `ifdef FSDB_DUMP
            $fsdbDumpfile("frl.fsdb");
            $fsdbDumpvars(0, FRL_tb);
        `else
            $dumpfile("frl.vcd");
            $dumpvars(0, FRL_tb);
        `endif

        $display("=======================================");
        $display("  FRL Testbench Start");
        $display("=======================================");

        $display("\n[Test 1] Reset");
        reset_dut();
        check_bit("not empty after reset", frl_read_empty, 1'b0);
        check_ptr("head pointer after reset", frl_head_ptr_to_frat, '0);

        $display("\n[Test 2] Initial free registers come out in order");
        for (int i = 0; i < FRL_SIZE; i++) begin
            read_free_reg(phy_addr);
            check_phy($sformatf("initial free reg[%0d]", i),
                      phy_addr,
                      PHY_REGISTER_FILE_WIDTH'(ARCH_REG_COUNT + i));
            check_ptr($sformatf("head pointer after read[%0d]", i),
                      frl_head_ptr_to_frat,
                      (i == FRL_SIZE - 1) ? {1'b1, {FRL_PTR_WIDTH{1'b0}}}
                                          : FRL_PTR_WIDTH'(i + 1));
        end
        check_bit("empty after all free regs allocated", frl_read_empty, 1'b1);

        $display("\n[Test 3] Read request while empty does not advance head");
        read_free_reg(phy_addr);
        check_bit("still empty after empty read", frl_read_empty, 1'b1);
        check_ptr("head pointer held on empty read",
                  frl_head_ptr_to_frat,
                  {1'b1, {FRL_PTR_WIDTH{1'b0}}});

        $display("\n[Test 4] Commit frees a physical register");
        commit_free_reg(5'd7);
        check_bit("not empty after commit", frl_read_empty, 1'b0);
        read_free_reg(phy_addr);
        check_phy("read committed free register", phy_addr, 5'd7);
        check_bit("empty after reading committed register", frl_read_empty, 1'b1);

        $display("\n[Test 5] Flush restores FRL head pointer");
        reset_dut();
        read_free_reg(phy_addr);
        read_free_reg(phy_addr);
        saved_head_ptr = frl_head_ptr_to_frat;

        read_free_reg(phy_addr);
        read_free_reg(phy_addr);
        restore_head(saved_head_ptr);

        read_free_reg(phy_addr);
        check_phy("flush replays first restored free reg",
                  phy_addr,
                  PHY_REGISTER_FILE_WIDTH'(ARCH_REG_COUNT + 2));
        read_free_reg(phy_addr);
        check_phy("flush replays second restored free reg",
                  phy_addr,
                  PHY_REGISTER_FILE_WIDTH'(ARCH_REG_COUNT + 3));

        $display("\n[Test 6] Simultaneous read and commit");
        reset_dut();
        for (int i = 0; i < FRL_SIZE - 1; i++) begin
            read_free_reg(phy_addr);
        end

        dis_frl_read               = 1'b1;
        rob_commit_pre_phy_address = 5'd6;
        rob_commit                 = 1'b1;
        rob_commit_reg_write       = 1'b1;
        @(posedge clk); #1;
        dis_frl_read               = 1'b0;
        rob_commit                 = 1'b0;
        rob_commit_reg_write       = 1'b0;
        check_phy("simultaneous read gets old head",
                  frl_read_phy_address,
                  PHY_REGISTER_FILE_WIDTH'(ARCH_REG_COUNT + FRL_SIZE - 1));
        check_bit("commit keeps list non-empty", frl_read_empty, 1'b0);

        read_free_reg(phy_addr);
        check_phy("next read gets committed register", phy_addr, 5'd6);

        $display("\n=======================================");
        $display("  FRL Testbench Done: %0d passed, %0d failed", pass_cnt, fail_cnt);
        $display("=======================================");

        if (fail_cnt == 0) begin
            $display("[PASS] FRL_tb completed successfully");
        end else begin
            $fatal(1, "[FAIL] FRL_tb found %0d failure(s)", fail_cnt);
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
