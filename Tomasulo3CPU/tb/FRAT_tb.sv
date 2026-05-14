// Disable width mismatch warnings from some simulators on unsized task arguments.
/* verilator lint_off WIDTH */
// verilog_lint: waive-start explicit-parameter-storage-type
/* verilator lint_off BLKSEQ */
`timescale 1ns/1ps

module FRAT_tb;

    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 6;
    parameter int unsigned ARCH_REG_COUNT          = 16;
    parameter int unsigned ARCH_REG_WIDTH          = $clog2(ARCH_REG_COUNT);
    parameter int unsigned NUM_CHECKPOINT          = 4;
    parameter int unsigned CHECKPOINT_PTR_WIDTH    = $clog2(NUM_CHECKPOINT);
    parameter int unsigned ROB_DEPTH               = 16;
    parameter int unsigned ROB_INDEX_WIDTH         = $clog2(ROB_DEPTH);
    parameter int unsigned FRL_SIZE                = 2**PHY_REGISTER_FILE_WIDTH - ARCH_REG_COUNT;
    parameter int unsigned FRL_PTR_WIDTH           = $clog2(FRL_SIZE);

    logic                                    clk;
    logic                                    rst_n;
    logic                                    is_branch;
    logic [ROB_INDEX_WIDTH-1:0]              rob_bottom_ptr;
    logic                                    dis_frat_reg_write;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]      rd_new_phy_address_in;
    logic [ARCH_REG_WIDTH-1:0]               rd_new_arch_address_in;
    logic                                    branch_mispredict;
    logic                                    rob_commit;
    logic [ROB_INDEX_WIDTH-1:0]              rob_top_ptr;
    logic [FRL_PTR_WIDTH:0]                  frl_head_ptr;
    logic [FRL_PTR_WIDTH:0]                  frat_frl_head_ptr;
    logic [ARCH_REG_WIDTH-1:0]               rd_prev_arch_address_in;
    logic [ARCH_REG_WIDTH-1:0]               rs1_arch_address_in;
    logic [ARCH_REG_WIDTH-1:0]               rs2_arch_address_in;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]      rd_prev_phy_address;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]      rs1_phy_address;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]      rs2_phy_address;
    logic                                    full;

    FRAT #(
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .ARCH_REG_COUNT         (ARCH_REG_COUNT),
        .ARCH_REG_WIDTH         (ARCH_REG_WIDTH),
        .NUM_CHECKPOINT         (NUM_CHECKPOINT),
        .CHECKPOINT_PTR_WIDTH   (CHECKPOINT_PTR_WIDTH),
        .ROB_DEPTH              (ROB_DEPTH),
        .ROB_INDEX_WIDTH        (ROB_INDEX_WIDTH),
        .FRL_SIZE               (FRL_SIZE),
        .FRL_PTR_WIDTH          (FRL_PTR_WIDTH)
    ) dut (
        .clk                   (clk),
        .rst_n                 (rst_n),
        .is_branch             (is_branch),
        .rob_bottom_ptr        (rob_bottom_ptr),
        .dis_frat_reg_write    (dis_frat_reg_write),
        .rd_new_phy_address_in (rd_new_phy_address_in),
        .rd_new_arch_address_in(rd_new_arch_address_in),
        .branch_mispredict     (branch_mispredict),
        .rob_commit            (rob_commit),
        .rob_top_ptr           (rob_top_ptr),
        .frl_head_ptr          (frl_head_ptr),
        .frat_frl_head_ptr     (frat_frl_head_ptr),
        .rd_prev_arch_address_in(rd_prev_arch_address_in),
        .rs1_arch_address_in   (rs1_arch_address_in),
        .rs2_arch_address_in   (rs2_arch_address_in),
        .rd_prev_phy_address   (rd_prev_phy_address),
        .rs1_phy_address       (rs1_phy_address),
        .rs2_phy_address       (rs2_phy_address),
        .full                  (full)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    int pass_cnt = 0;
    int fail_cnt = 0;

    logic [PHY_REGISTER_FILE_WIDTH-1:0] exp_map [ARCH_REG_COUNT];

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

    task automatic check_frl_ptr(
        input string                 tag,
        input logic [FRL_PTR_WIDTH:0] actual,
        input logic [FRL_PTR_WIDTH:0] expected
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
        is_branch              = 1'b0;
        rob_bottom_ptr         = '0;
        dis_frat_reg_write     = 1'b0;
        rd_new_phy_address_in  = '0;
        rd_new_arch_address_in = '0;
        branch_mispredict      = 1'b0;
        rob_commit             = 1'b0;
        rob_top_ptr            = '0;
        frl_head_ptr           = '0;
        rd_prev_arch_address_in = '0;
        rs1_arch_address_in    = '0;
        rs2_arch_address_in    = '0;
    endtask

    task automatic reset_dut();
        rst_n = 1'b0;
        clear_inputs();
        for (int i = 0; i < ARCH_REG_COUNT; i++) begin
            exp_map[i] = PHY_REGISTER_FILE_WIDTH'(i);
        end

        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;
    endtask

    task automatic set_read_addrs(
        input logic [ARCH_REG_WIDTH-1:0] rd_arch,
        input logic [ARCH_REG_WIDTH-1:0] rs1_arch,
        input logic [ARCH_REG_WIDTH-1:0] rs2_arch
    );
        rd_prev_arch_address_in = rd_arch;
        rs1_arch_address_in     = rs1_arch;
        rs2_arch_address_in     = rs2_arch;
        #1;
    endtask

    task automatic expect_read(
        input string                     tag,
        input logic [ARCH_REG_WIDTH-1:0] rd_arch,
        input logic [ARCH_REG_WIDTH-1:0] rs1_arch,
        input logic [ARCH_REG_WIDTH-1:0] rs2_arch
    );
        set_read_addrs(rd_arch, rs1_arch, rs2_arch);
        check_phy({tag, " rd_prev"}, rd_prev_phy_address, exp_map[rd_arch]);
        check_phy({tag, " rs1"},     rs1_phy_address,     exp_map[rs1_arch]);
        check_phy({tag, " rs2"},     rs2_phy_address,     exp_map[rs2_arch]);
    endtask

    task automatic dispatch_write(
        input logic [ARCH_REG_WIDTH-1:0]          arch_addr,
        input logic [PHY_REGISTER_FILE_WIDTH-1:0] phy_addr
    );
        rd_new_arch_address_in = arch_addr;
        rd_new_phy_address_in  = phy_addr;
        dis_frat_reg_write     = 1'b1;
        @(posedge clk); #1;
        dis_frat_reg_write     = 1'b0;
        exp_map[arch_addr]     = phy_addr;
    endtask

    task automatic branch_checkpoint(
        input logic [ROB_INDEX_WIDTH-1:0] tag,
        input logic [FRL_PTR_WIDTH:0]     head_ptr
    );
        rob_bottom_ptr = tag;
        frl_head_ptr   = head_ptr;
        is_branch      = 1'b1;
        @(posedge clk); #1;
        is_branch      = 1'b0;
    endtask

    task automatic commit_branch(input logic [ROB_INDEX_WIDTH-1:0] tag);
        rob_top_ptr = tag;
        rob_commit  = 1'b1;
        @(posedge clk); #1;
        rob_commit  = 1'b0;
    endtask

    task automatic mispredict_restore();
        branch_mispredict = 1'b1;
        @(posedge clk); #1;
        branch_mispredict = 1'b0;
    endtask

    logic [PHY_REGISTER_FILE_WIDTH-1:0] checkpoint_map [ARCH_REG_COUNT];
    logic [FRL_PTR_WIDTH:0]             saved_frl_head;

    initial begin
        `ifdef FSDB_DUMP
            $fsdbDumpfile("frat.fsdb");
            $fsdbDumpvars(0, FRAT_tb);
        `else
            $dumpfile("frat.vcd");
            $dumpvars(0, FRAT_tb);
        `endif

        $display("=======================================");
        $display("  FRAT Testbench Start");
        $display("=======================================");

        $display("\n[Test 1] Reset initializes architectural registers to matching physical registers");
        reset_dut();
        for (int i = 0; i < ARCH_REG_COUNT; i += 3) begin
            expect_read($sformatf("reset map[%0d]", i),
                        ARCH_REG_WIDTH'(i),
                        ARCH_REG_WIDTH'((i + 1) % ARCH_REG_COUNT),
                        ARCH_REG_WIDTH'((i + 2) % ARCH_REG_COUNT));
        end
        check_bit("checkpoint FIFO not full after reset", full, 1'b0);

        $display("\n[Test 2] Dispatch register writes update only the selected architectural mapping");
        dispatch_write(ARCH_REG_WIDTH'(3),  PHY_REGISTER_FILE_WIDTH'(33));
        dispatch_write(ARCH_REG_WIDTH'(10), PHY_REGISTER_FILE_WIDTH'(44));
        expect_read("after two dispatch writes",
                    ARCH_REG_WIDTH'(3), ARCH_REG_WIDTH'(10), ARCH_REG_WIDTH'(4));

        $display("\n[Test 3] Branch checkpoint restores FRAT and FRL head on mispredict");
        saved_frl_head = {1'b0, FRL_PTR_WIDTH'(7)};
        branch_checkpoint(ROB_INDEX_WIDTH'(5), saved_frl_head);
        for (int i = 0; i < ARCH_REG_COUNT; i++) begin
            checkpoint_map[i] = exp_map[i];
        end

        dispatch_write(ARCH_REG_WIDTH'(3),  PHY_REGISTER_FILE_WIDTH'(50));
        dispatch_write(ARCH_REG_WIDTH'(11), PHY_REGISTER_FILE_WIDTH'(51));
        expect_read("before mispredict restore",
                    ARCH_REG_WIDTH'(3), ARCH_REG_WIDTH'(11), ARCH_REG_WIDTH'(10));

        for (int i = 0; i < ARCH_REG_COUNT; i++) begin
            exp_map[i] = checkpoint_map[i];
        end
        mispredict_restore();
        expect_read("after mispredict restore",
                    ARCH_REG_WIDTH'(3), ARCH_REG_WIDTH'(11), ARCH_REG_WIDTH'(10));
        check_frl_ptr("FRL head restored from oldest checkpoint",
                      frat_frl_head_ptr,
                      saved_frl_head);

        $display("\n[Test 4] Committing a branch releases its checkpoint");
        reset_dut();
        branch_checkpoint(ROB_INDEX_WIDTH'(2), {1'b0, FRL_PTR_WIDTH'(3)});
        commit_branch(ROB_INDEX_WIDTH'(2));
        check_bit("checkpoint FIFO not full after matching branch commit", full, 1'b0);

        branch_checkpoint(ROB_INDEX_WIDTH'(6), {1'b0, FRL_PTR_WIDTH'(4)});
        dispatch_write(ARCH_REG_WIDTH'(1), PHY_REGISTER_FILE_WIDTH'(40));
        exp_map[1] = PHY_REGISTER_FILE_WIDTH'(1);
        mispredict_restore();
        expect_read("restore uses remaining checkpoint after earlier commit",
                    ARCH_REG_WIDTH'(1), ARCH_REG_WIDTH'(2), ARCH_REG_WIDTH'(3));
        check_frl_ptr("remaining checkpoint FRL head",
                      frat_frl_head_ptr,
                      {1'b0, FRL_PTR_WIDTH'(4)});

        $display("\n[Test 5] Full checkpoint FIFO blocks additional checkpoint allocation");
        reset_dut();
        for (int i = 0; i < NUM_CHECKPOINT; i++) begin
            branch_checkpoint(ROB_INDEX_WIDTH'(8 + i),
                              {1'b0, FRL_PTR_WIDTH'(10 + i)});
        end
        check_bit("checkpoint FIFO full after all entries allocated", full, 1'b1);

        branch_checkpoint(ROB_INDEX_WIDTH'(15), {1'b0, FRL_PTR_WIDTH'(22)});
        check_bit("full remains asserted when branch dispatch is blocked", full, 1'b1);

        commit_branch(ROB_INDEX_WIDTH'(8));
        check_bit("one branch commit makes room for another checkpoint", full, 1'b0);

        $display("\n=======================================");
        $display("  FRAT Testbench Done: %0d passed, %0d failed", pass_cnt, fail_cnt);
        $display("=======================================");

        if (fail_cnt == 0) begin
            $display("[PASS] FRAT_tb completed successfully");
        end else begin
            $fatal(1, "[FAIL] FRAT_tb found %0d failure(s)", fail_cnt);
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
