module RAS #(
    parameter int unsigned INSTR_WIDTH = 32,
    parameter int unsigned DEPTH = 4
) (
    input logic clk,
    input logic rst_n,
    
    input logic [INSTR_WIDTH-1:0]   dis_pcplus4,
    input logic                     dis_ras_jr31_inst,
    input logic                     dis_ras_jal_inst,

    output logic [INSTR_WIDTH-1:0]  ras_addr
);
    // RAS implementation: a simple stack of return addresses
    // On a JAL, push the return address (PC+4) onto the stack
    // On a JR with $ra, pop the top address from the stack and use it as the jump target
    // The RAS can hold up to 8 return addresses (for nested calls)
    // If the RAS is empty on a JR $ra, we can treat it as a misprediction and flush the pipeline

    sync_lifo #(
        .DATA_WIDTH(INSTR_WIDTH),
        .DEPTH(DEPTH),
        .ROUND_ROBIN(1),
        .UNDERFLOW_PROTECT(0),
        .ALLOW_PUSH_POP_SAME_CYCLE(1)
    ) ras_stack (
        .clk(clk),
        .rst_n(rst_n),
        .push(dis_ras_jal_inst),
        .pop(dis_ras_jr31_inst),
        .data_in(dis_pcplus4),
        .data_out(ras_addr),
        .empty(),
        .full()
    );

    
endmodule