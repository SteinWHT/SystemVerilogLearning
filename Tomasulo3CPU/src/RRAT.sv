// Currently this is a useless module
// FRAT stores the states of the architectural registers of each checkpoint
// ROB stores the previous physical register index for freeing physical registers
// And maybe this module can be used in future exception handling
// SO, there is no output port at least now
// TODO: check if this is correct
module RRAT #(
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned ARCH_REG_COUNT = 32,
    parameter int unsigned ARCH_REG_WIDTH = $clog2(ARCH_REG_COUNT),
    parameter int unsigned NUM_CHECKPOINT = 8,
    parameter int unsigned CHECKPOINT_PTR_WIDTH = $clog2(NUM_CHECKPOINT)
) (
    input logic clk,
    input logic rst_n,

    // ROB interface
    input logic [ARCH_REG_WIDTH-1:0] rob_commit_rd_arch_addr,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] rob_commit_curr_phy_addr,
    input logic rob_commit,
    input logic rob_commit_reg_write

    // Output
);
    // Maybe later we need to send the whole array to the FRAT or other modules for recovery
    // So we use a register array instead of a dual port RAM
    logic [PHY_REGISTER_FILE_WIDTH-1:0] rrat_array [ARCH_REG_COUNT];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < ARCH_REG_COUNT; i++) begin
                rrat_array[i] <= PHY_REGISTER_FILE_WIDTH'(i);
            end
        end
        else begin
            if (rob_commit && rob_commit_reg_write) begin
                rrat_array[rob_commit_rd_arch_addr] <= rob_commit_curr_phy_addr;
            end
        end
    end
endmodule
