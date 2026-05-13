`timescale 1ns/1ps
module RAS #(
    parameter int unsigned IMEM_DEPTH = 32,
    parameter int unsigned IMEM_DEPTH_WORD = IMEM_DEPTH - 2,
    parameter int unsigned DEPTH = 4
) (
    input logic clk,
    input logic rst_n,

    input logic [IMEM_DEPTH-1:0]        dis_pc_plus4,
    input logic                         dis_ras_jr31_inst,
    input logic                         dis_ras_jal_inst,

    output logic [IMEM_DEPTH_WORD-1:0]  ras_addr
);

    logic unused_empty, unused_full;
    // RAS implementation: a simple stack of return addresses
    // On a JAL, push the return address (PC+4) onto the stack
    // On a JR with $ra, pop the top address from the stack and use it as the jump target
    // The RAS can hold up to 8 return addresses (for nested calls)
    // If the RAS is empty on a JR $ra, we can treat it as a misprediction and flush the pipeline

    sync_lifo #(
        .DATA_WIDTH(IMEM_DEPTH_WORD),
        .DEPTH(DEPTH),
        .ROUND_ROBIN(1),
        .UNDERFLOW_PROTECT(1),
        .ALLOW_PUSH_POP_SAME_CYCLE(1)
    ) ras_stack (
        .clk(clk),
        .rst_n(rst_n),
        .push(dis_ras_jal_inst),
        .pop(dis_ras_jr31_inst),
        .data_in(dis_pc_plus4[IMEM_DEPTH-1:2]),
        .data_out(ras_addr),
        .empty(unused_empty),
        .full(unused_full)
    );

endmodule
