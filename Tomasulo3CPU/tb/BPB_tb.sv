// Disable width mismatch warnings from some simulators on unsized task arguments.
/* verilator lint_off WIDTH */
// verilog_lint: waive-start explicit-parameter-storage-type
/* verilator lint_off BLKSEQ */
`timescale 1ns/1ps

module BPB_tb;

    parameter int unsigned BUFFER_WIDTH = 3;
    parameter int unsigned FSM_WIDTH    = 2;
    parameter int unsigned BUFFER_SIZE  = 1 << BUFFER_WIDTH;

    logic                    clk;
    logic                    rst_n;
    logic [BUFFER_WIDTH-1:0] dis_bpb_branch_pc_bits;
    logic                    dis_bpb_branch;
    logic                    bpb_branch_prediction;
    logic                    dis_cdb_upd_branch;
    logic [BUFFER_WIDTH-1:0] dis_cdb_upd_branch_addr;
    logic                    dis_cdb_branch_outcome;

    BPB #(
        .BUFFER_WIDTH(BUFFER_WIDTH),
        .FSM_WIDTH   (FSM_WIDTH)
    ) dut (
        .clk                       (clk),
        .rst_n                     (rst_n),
        .dis_bpb_branch_pc_bits    (dis_bpb_branch_pc_bits),
        .dis_bpb_branch            (dis_bpb_branch),
        .bpb_branch_prediction     (bpb_branch_prediction),
        .dis_cdb_upd_branch        (dis_cdb_upd_branch),
        .dis_cdb_upd_branch_addr   (dis_cdb_upd_branch_addr),
        .dis_cdb_branch_outcome    (dis_cdb_branch_outcome)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    int pass_cnt = 0;
    int fail_cnt = 0;

    logic [FSM_WIDTH-1:0] expected_counter [BUFFER_SIZE];

    task automatic check_bit(string tag, logic actual, logic expected);
        if (actual !== expected) begin
            $error("[FAIL] %s: got %0b, want %0b @ %0t", tag, actual, expected, $time);
            fail_cnt++;
        end else begin
            pass_cnt++;
        end
    endtask

    task automatic reset_dut();
        rst_n                   = 1'b0;
        dis_bpb_branch_pc_bits  = '0;
        dis_bpb_branch          = 1'b0;
        dis_cdb_upd_branch      = 1'b0;
        dis_cdb_upd_branch_addr = '0;
        dis_cdb_branch_outcome  = 1'b0;

        for (int i = 0; i < BUFFER_SIZE; i++) begin
            expected_counter[i] = '0;
        end

        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;
    endtask

    task automatic read_prediction(
        input  logic [BUFFER_WIDTH-1:0] addr,
        output logic                    prediction
    );
        dis_bpb_branch_pc_bits = addr;
        dis_bpb_branch         = 1'b1;
        @(posedge clk); #1;
        prediction             = bpb_branch_prediction;
        dis_bpb_branch         = 1'b0;
    endtask

    task automatic expect_prediction(
        input logic [BUFFER_WIDTH-1:0] addr,
        input string                   tag
    );
        logic prediction;
        read_prediction(addr, prediction);
        check_bit(tag, prediction, expected_counter[addr][FSM_WIDTH-1]);
    endtask

    task automatic update_expected(
        input logic [BUFFER_WIDTH-1:0] addr,
        input logic                    taken
    );
        if (taken) begin
            if (expected_counter[addr] != {FSM_WIDTH{1'b1}}) begin
                expected_counter[addr]++;
            end
        end else begin
            if (expected_counter[addr] != '0) begin
                expected_counter[addr]--;
            end
        end
    endtask

    task automatic update_branch(
        input logic [BUFFER_WIDTH-1:0] addr,
        input logic                    taken
    );
        // BPB reads the current counter through dual_port_memory port B before
        // writing the next counter, so give that read path a cycle to settle.
        dis_cdb_upd_branch_addr = addr;
        dis_cdb_upd_branch      = 1'b0;
        @(posedge clk); #1;

        dis_cdb_branch_outcome = taken;
        dis_cdb_upd_branch     = 1'b1;
        @(posedge clk); #1;

        dis_cdb_upd_branch = 1'b0;
        update_expected(addr, taken);

        // Let port B observe the newly written counter before another update.
        @(posedge clk); #1;
    endtask

    initial begin
        `ifdef FSDB_DUMP
            $fsdbDumpfile("bpb.fsdb");
            $fsdbDumpvars(0, BPB_tb);
        `else
            $dumpfile("bpb.vcd");
            $dumpvars(0, BPB_tb);
        `endif

        $display("=======================================");
        $display("  BPB Testbench Start");
        $display("=======================================");

        $display("\n[Test 1] Reset predicts not taken for every entry");
        reset_dut();
        for (int i = 0; i < BUFFER_SIZE; i++) begin
            expect_prediction(BUFFER_WIDTH'(i), $sformatf("reset prediction[%0d]", i));
        end

        $display("\n[Test 2] Taken outcomes move one entry toward taken");
        update_branch(3'd2, 1'b1);
        expect_prediction(3'd2, "addr 2 after one taken");

        update_branch(3'd2, 1'b1);
        expect_prediction(3'd2, "addr 2 after two taken");

        update_branch(3'd2, 1'b1);
        expect_prediction(3'd2, "addr 2 after three taken");

        update_branch(3'd2, 1'b1);
        expect_prediction(3'd2, "addr 2 saturates strongly taken");

        $display("\n[Test 3] Not-taken outcomes move the same entry back");
        update_branch(3'd2, 1'b0);
        expect_prediction(3'd2, "addr 2 after one not-taken");

        update_branch(3'd2, 1'b0);
        expect_prediction(3'd2, "addr 2 after two not-taken");

        update_branch(3'd2, 1'b0);
        expect_prediction(3'd2, "addr 2 after three not-taken");

        update_branch(3'd2, 1'b0);
        expect_prediction(3'd2, "addr 2 saturates strongly not-taken");

        $display("\n[Test 4] Different BPB entries update independently");
        update_branch(3'd0, 1'b1);
        update_branch(3'd0, 1'b1);
        update_branch(3'd5, 1'b1);

        expect_prediction(3'd0, "addr 0 predicts taken");
        expect_prediction(3'd5, "addr 5 still weak not-taken");
        expect_prediction(3'd2, "addr 2 remains not-taken");

        $display("\n[Test 5] Read disabled defaults to not-taken");
        dis_bpb_branch_pc_bits = 3'd0;
        dis_bpb_branch         = 1'b0;
        @(posedge clk); #1;
        check_bit("prediction defaults to not-taken when read disabled",
                  bpb_branch_prediction, 1'b0);

        $display("\n=======================================");
        $display("  BPB Testbench Done: %0d passed, %0d failed", pass_cnt, fail_cnt);
        $display("=======================================");

        if (fail_cnt == 0) begin
            $display("[PASS] BPB_tb completed successfully");
        end else begin
            $fatal(1, "[FAIL] BPB_tb found %0d failure(s)", fail_cnt);
        end
        $finish;
    end

    // Timeout guard
    initial begin
        #100_000;
        $error("TIMEOUT");
        $finish;
    end

endmodule
/* verilator lint_on WIDTH */
/* verilator lint_on BLKSEQ */
// verilog_lint: waive-stop explicit-parameter-storage-type
