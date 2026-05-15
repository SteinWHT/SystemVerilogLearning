// Disable width mismatch warnings from some simulators on unsized task arguments.
/* verilator lint_off WIDTH */
// verilog_lint: waive-start explicit-parameter-storage-type
/* verilator lint_off BLKSEQ */
`timescale 1ns/1ps

module RAS_tb;

    parameter int unsigned IMEM_DEPTH      = 32;
    parameter int unsigned IMEM_DEPTH_WORD = IMEM_DEPTH - 1;
    parameter int unsigned DEPTH           = 4;

    logic                         clk;
    logic                         rst_n;
    logic [IMEM_DEPTH-1:0]        dis_pc_plus4;
    logic                         dis_ras_jr31_inst;
    logic                         dis_ras_jal_inst;
    logic [IMEM_DEPTH_WORD-1:0]   ras_addr;

    RAS #(
        .IMEM_DEPTH     (IMEM_DEPTH),
        .IMEM_DEPTH_WORD(IMEM_DEPTH_WORD),
        .DEPTH          (DEPTH)
    ) dut (
        .clk                (clk),
        .rst_n              (rst_n),
        .dis_pc_plus4       (dis_pc_plus4),
        .dis_ras_jr31_inst  (dis_ras_jr31_inst),
        .dis_ras_jal_inst   (dis_ras_jal_inst),
        .ras_addr           (ras_addr)
    );

    initial clk = 1'b0;
    always #5 clk = ~clk;

    int pass_cnt = 0;
    int fail_cnt = 0;

    task automatic check_word(
        input string                         tag,
        input logic [IMEM_DEPTH_WORD-1:0]   actual,
        input logic [IMEM_DEPTH_WORD-1:0]   expected
    );
        if (actual !== expected) begin
            $error("[FAIL] %s: got 0x%0h, want 0x%0h @ %0t",
                   tag, actual, expected, $time);
            fail_cnt++;
        end else begin
            pass_cnt++;
        end
    endtask

    function automatic logic [IMEM_DEPTH_WORD-1:0] ifq_jmp_addr(
        input logic [IMEM_DEPTH-1:0] pc_plus4
    );
        ifq_jmp_addr = pc_plus4[IMEM_DEPTH-1:1];
    endfunction

    task automatic reset_dut();
        rst_n                 = 1'b0;
        dis_pc_plus4          = '0;
        dis_ras_jr31_inst     = 1'b0;
        dis_ras_jal_inst      = 1'b0;

        repeat (2) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk); #1;
    endtask

    task automatic idle_cycle();
        dis_ras_jal_inst  = 1'b0;
        dis_ras_jr31_inst = 1'b0;
        @(posedge clk); #1;
    endtask

    task automatic push_return_addr(input logic [IMEM_DEPTH-1:0] pc_plus4);
        dis_pc_plus4      = pc_plus4;
        dis_ras_jal_inst  = 1'b1;
        dis_ras_jr31_inst = 1'b0;
        @(posedge clk); #1;
        dis_ras_jal_inst  = 1'b0;
    endtask

    task automatic pop_return_addr(output logic [IMEM_DEPTH_WORD-1:0] popped_addr);
        dis_ras_jal_inst  = 1'b0;
        dis_ras_jr31_inst = 1'b1;
        #1;
        popped_addr       = ras_addr;
        @(posedge clk); #1;
        dis_ras_jr31_inst = 1'b0;
    endtask

    task automatic push_and_pop_same_cycle(
        input  logic [IMEM_DEPTH-1:0]      pc_plus4,
        output logic [IMEM_DEPTH_WORD-1:0] ras_out
    );
        dis_pc_plus4      = pc_plus4;
        dis_ras_jal_inst  = 1'b1;
        dis_ras_jr31_inst = 1'b1;
        #1;
        ras_out           = ras_addr;
        @(posedge clk); #1;
        dis_ras_jal_inst  = 1'b0;
        dis_ras_jr31_inst = 1'b0;
    endtask

    logic [IMEM_DEPTH_WORD-1:0] popped_addr;
    logic [IMEM_DEPTH_WORD-1:0] simul_addr;

    initial begin
        `ifdef FSDB_DUMP
            $fsdbDumpfile("ras.fsdb");
            $fsdbDumpvars(0, RAS_tb);
        `else
            $dumpfile("ras.vcd");
            $dumpvars(0, RAS_tb);
        `endif

        $display("=======================================");
        $display("  RAS Testbench Start");
        $display("=======================================");

        $display("\n[Test 1] Reset");
        reset_dut();
        check_word("ras_addr after reset", ras_addr, IMEM_DEPTH_WORD'(32'hDEAD_BEEF));

        $display("\n[Test 2] Single call and return");
        push_return_addr(32'h0000_1004);
        check_word("push exposes new return jump address", ras_addr, ifq_jmp_addr(32'h0000_1004));
        pop_return_addr(popped_addr);
        check_word("pop returns pushed jump address", popped_addr, ifq_jmp_addr(32'h0000_1004));
        pop_return_addr(popped_addr);
        check_word("empty pop returns last popped address", popped_addr, ifq_jmp_addr(32'h0000_1004));

        $display("\n[Test 3] Nested calls pop in LIFO order");
        reset_dut();
        push_return_addr(32'h0000_2004);
        push_return_addr(32'h0000_3004);
        push_return_addr(32'h0000_4004);

        pop_return_addr(popped_addr);
        check_word("nested pop 0", popped_addr, ifq_jmp_addr(32'h0000_4004));
        pop_return_addr(popped_addr);
        check_word("nested pop 1", popped_addr, ifq_jmp_addr(32'h0000_3004));
        pop_return_addr(popped_addr);
        check_word("nested pop 2", popped_addr, ifq_jmp_addr(32'h0000_2004));
        pop_return_addr(popped_addr);
        check_word("nested empty pop repeats last", popped_addr, ifq_jmp_addr(32'h0000_2004));

        $display("\n[Test 4] Full stack round-robin overwrite");
        reset_dut();
        push_return_addr(32'h0000_5004);
        push_return_addr(32'h0000_6004);
        push_return_addr(32'h0000_7004);
        push_return_addr(32'h0000_8004);
        push_return_addr(32'h0000_9004);

        pop_return_addr(popped_addr);
        check_word("round-robin newest", popped_addr, ifq_jmp_addr(32'h0000_9004));
        pop_return_addr(popped_addr);
        check_word("round-robin next 0", popped_addr, ifq_jmp_addr(32'h0000_8004));
        pop_return_addr(popped_addr);
        check_word("round-robin next 1", popped_addr, ifq_jmp_addr(32'h0000_7004));
        pop_return_addr(popped_addr);
        check_word("round-robin next 2", popped_addr, ifq_jmp_addr(32'h0000_6004));
        pop_return_addr(popped_addr);
        check_word("round-robin empty pop repeats last", popped_addr, ifq_jmp_addr(32'h0000_6004));

        $display("\n[Test 5] Simultaneous call and return");
        reset_dut();
        push_return_addr(32'h0000_A004);
        push_return_addr(32'h0000_B004);

        push_and_pop_same_cycle(32'h0000_C004, simul_addr);
        check_word("same-cycle push/pop drives incoming jump address", simul_addr, ifq_jmp_addr(32'h0000_C004));

        pop_return_addr(popped_addr);
        check_word("same-cycle push/pop leaves previous top", popped_addr, ifq_jmp_addr(32'h0000_B004));
        pop_return_addr(popped_addr);
        check_word("same-cycle push/pop leaves older entry", popped_addr, ifq_jmp_addr(32'h0000_A004));
        pop_return_addr(popped_addr);
        check_word("same-cycle empty pop repeats last", popped_addr, ifq_jmp_addr(32'h0000_A004));

        idle_cycle();

        $display("\n=======================================");
        $display("  RAS Testbench Done: %0d passed, %0d failed", pass_cnt, fail_cnt);
        $display("=======================================");

        if (fail_cnt == 0) begin
            $display("[PASS] RAS_tb completed successfully");
        end else begin
            $fatal(1, "[FAIL] RAS_tb found %0d failure(s)", fail_cnt);
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
