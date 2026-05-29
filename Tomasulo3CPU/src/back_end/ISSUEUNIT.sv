// Some cycles are set as parameters
// But in fact they are constants in the implementation
// TODO: implement a parametized module for the issue logic

// We don't introduce the flush here
// Namely, even if the exe modules are ready because of the flush, we still view them as busy
module ISSUEUNIT #(
    parameter int unsigned DIV_CYCLES = 64,
    parameter int unsigned MUL_CYCLES = 4,
    parameter int unsigned INT_CYCLES = 1,
    parameter int unsigned LD_ST_CYCLES = 1
) (
    input logic clk,
    input logic rst_n,

    // int
    input  logic ready_int,
    output logic issue_int,

    // div
    input  logic ready_div,
    input  logic div_exe_ready,
    output logic issue_div,

    // mul
    input  logic ready_mul,
    output logic issue_mul,

    // LSB (load/store buffer) — ISSUEUNIT drains completed mem ops to CDB.
    // LSQ issues into LSB independently when LSB asserts iss_lsb_ready.
    input  logic ready_ld_buf,
    output logic issue_ld_buf
);

    localparam int unsigned DIV_COUNTER_WIDTH = $clog2(DIV_CYCLES + 1) + 1;
    localparam logic [DIV_COUNTER_WIDTH - 1:0] DIV_MUL_CONFLICT_COUNT = DIV_COUNTER_WIDTH'(MUL_CYCLES);
    localparam logic [DIV_COUNTER_WIDTH - 1:0] DIV_NEXT_CONFLICT_COUNT = DIV_COUNTER_WIDTH'(1);

    logic                                 priority_int_ld_st, priority_int_ld_st_next;
    logic [DIV_COUNTER_WIDTH - 1:0]       div_complete_counter;
    logic [MUL_CYCLES - 1:0]              mul_complete_counter;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            priority_int_ld_st      <= '0;
            div_complete_counter    <= '0;
            mul_complete_counter    <= '0;
        end else begin
            // There is no conflict between issue_div and div_complete_counter:
            // issue_div is asserted only when div_complete_counter is 0.
            if (issue_div) begin
                div_complete_counter <= DIV_COUNTER_WIDTH'(DIV_CYCLES + 1);
            end else if (div_complete_counter > 0) begin
                div_complete_counter <= div_complete_counter - 1;
            end

            // MUL is pipelined, so each issue is inserted into a completion shift register.
            // Bit 1 marks a MUL that will complete in the same slot as a 1-cycle issue now.
            mul_complete_counter <= {issue_mul, mul_complete_counter[MUL_CYCLES - 1:1]};

            priority_int_ld_st <= priority_int_ld_st_next;
        end
    end
    // Issue logic / priority logic:
    // 1. Issue the div: non-pipelined, 7 cycles
    // 2. Issue the mul: pipelined, 4 cycles
    // 3. Issue the int: 1 cycle or Issue the ld/st: 1 cycle
    // an LRU to track the priority of the int and ld/st

    // Rules:
    // 1. If the div is ready and the div is executable, issue the div
    // 2. If the mul is ready and  if a DIV will not be completing 4 cycles later
    // 3. If the int is ready or the ld/st is ready, issue the int or the ld/st according to the LRU
    //    if no other instruction will complete in the next cycle
    // 1: int, 0: ld/st

    always_comb begin
        issue_int               = 0;
        issue_div               = 0;
        issue_mul               = 0;
        issue_ld_buf            = 0;
        priority_int_ld_st_next = priority_int_ld_st;

        if (ready_div && div_exe_ready && div_complete_counter == 0) begin
            issue_div = 1;
        end else if (ready_mul && (div_complete_counter != DIV_MUL_CONFLICT_COUNT)) begin
            issue_mul = 1;
        end else if ((div_complete_counter != DIV_NEXT_CONFLICT_COUNT && !mul_complete_counter[1])) begin
            if(ready_int && ready_ld_buf) begin
                if (priority_int_ld_st == 1'b1) begin
                    issue_int = 1;
                    priority_int_ld_st_next = 1'b0;
                end else if (priority_int_ld_st == 1'b0) begin
                    issue_ld_buf = 1;
                    priority_int_ld_st_next = 1'b1;
                end
            end else if (ready_ld_buf) begin
                issue_ld_buf = 1;
                priority_int_ld_st_next = 1'b1;
            end else if (ready_int) begin
                issue_int = 1;
                priority_int_ld_st_next = 1'b0;
            end
        end
    end

    // synthesis translate_off
    ISSUE_PRIORITY_RULE:assert property (@(posedge clk) disable iff (!rst_n) DIV_CYCLES > MUL_CYCLES)
    else $error("DIV_CYCLES must be greater than MUL_CYCLES to ensure correct priority logic");
    MUL_CYCLES_RULE:assert property (@(posedge clk) disable iff (!rst_n) MUL_CYCLES > 1)
    else $error("MUL_CYCLES must be greater than 1 for the MUL completion shift register");
    // synthesis translate_on
endmodule
