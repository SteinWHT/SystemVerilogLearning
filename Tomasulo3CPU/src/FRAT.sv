// Front-end Register Alias Table
// 128 pyhsical register file index
// only support 2^N CHECKPOINT
module FRAT #(
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned ARCH_REG_COUNT = 32,
    localparam int unsigned ARCH_REG_WIDTH = $clog2(ARCH_REG_COUNT),
    // NUM_CHECKPOINT should be 2^N due to the round robin pointer
    parameter int unsigned NUM_CHECKPOINT = 8,
    localparam int unsigned CHECKPOINT_PTR_WIDTH = $clog2(NUM_CHECKPOINT),
    parameter int unsigned ROB_DEPTH = 32,
    localparam int unsigned ROB_INDEX_WIDTH = $clog2(ROB_DEPTH),
    localparam int unsigned FRL_SIZE = 2**PHY_REGISTER_FILE_WIDTH - ARCH_REG_COUNT,
    localparam int unsigned FRL_PTR_WIDTH = $clog2(FRL_SIZE)
) (
    input logic clk,
    input logic rst_n,
    
    // DISPATCH
    input logic                                 is_branch,
    input logic [ROB_INDEX_WIDTH-1:0]           rob_bottom_ptr,
    input logic                                 dis_frat_reg_write,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   rd_new_phy_address_in,
    input logic [ARCH_REG_WIDTH-1:0]            rd_new_arch_address_in,

    // COMMIT
    input logic                                 branch_mispredict,
    input logic                                 rob_commit,
    input logic [ROB_INDEX_WIDTH-1:0]           rob_top_ptr,

    // FRL interface
    input logic [FRL_PTR_WIDTH:0]              frl_head_ptr,
    output logic [FRL_PTR_WIDTH:0]             frat_frl_head_ptr,

    //
    input logic [ARCH_REG_WIDTH-1:0]            rd_prev_arch_address_in,
    input logic [ARCH_REG_WIDTH-1:0]            rs1_arch_address_in,
    input logic [ARCH_REG_WIDTH-1:0]            rs2_arch_address_in,

    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  rd_prev_phy_address,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  rs1_phy_address,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  rs2_phy_address,

    output logic full
);
    // FRAT array: maps architectural register index to physical register index
    // I don't use the circular buffer approach for FRAT
    logic [PHY_REGISTER_FILE_WIDTH-1:0] frat_array [0:ARCH_REG_COUNT-1];
    logic [PHY_REGISTER_FILE_WIDTH-1:0] checkpoint_frat_array [0:NUM_CHECKPOINT-1][0:ARCH_REG_COUNT-1];

    logic [ROB_INDEX_WIDTH-1:0] checkpoint_tag_array [0:CHECKPOINT_PTR_WIDTH-1];
    logic [FRL_PTR_WIDTH:0] checkpoint_frl_head_ptr [0:CHECKPOINT_PTR_WIDTH-1];

    // round robin pointer
    logic [CHECKPOINT_PTR_WIDTH:0] checkpoint_head, checkpoint_tail;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < ARCH_REG_COUNT; i++) begin
                frat_array[i] <= i; // initialize
            end

            checkpoint_head <= '0;
            checkpoint_tail <= '0;
            for (int i = 0; i < CHECKPOINT_PTR_WIDTH; i++) begin
                checkpoint_tag_array[i] <= '0;
            end
        end else begin
            // branch commit: taken branch
            if (rob_commit && rob_top_ptr == checkpoint_tag_array[checkpoint_tail]) begin
                checkpoint_tail <= checkpoint_tail + 1;
            end

            // branch commit: not taken branch
            if (branch_mispredict) begin
                // On branch mispredict, restore the FRAT from the checkpoint
                for (int i = 0; i < ARCH_REG_COUNT; i++) begin
                    frat_array[i] <= checkpoint_frat_array[checkpoint_tail][i];
                end

                checkpoint_head <= checkpoint_tail;
            end

            // branch dispatch
            if (is_branch && !full) begin
                checkpoint_head <= checkpoint_head + 1;
                checkpoint_tag_array[checkpoint_head] <= rob_bottom_ptr;
                checkpoint_frl_head_ptr[checkpoint_head] <= frl_head_ptr;
                // On branch, create a checkpoint of the current FRAT state
                for (int i = 0; i < ARCH_REG_COUNT; i++) begin
                    checkpoint_frat_array[checkpoint_head][i] <= frat_array[i];
                end
            end

            // normal instruction dispatch
            // Commonly if it's a branch, the frat_reg_write should be 0, so the FRAT is not updated
            // TODO: ASSERTION
            if (dis_frat_reg_write) begin
                frat_array[rd_new_arch_address_in] <= rd_new_phy_address_in;
            end
        end
    end

    assign rd_prev_phy_address  =   frat_array[rd_prev_arch_address_in];
    assign rs1_phy_address      =   frat_array[rs1_arch_address_in];
    assign rs2_phy_address      =   frat_array[rs2_arch_address_in];

    assign full = (checkpoint_head[CHECKPOINT_PTR_WIDTH] != checkpoint_tail[CHECKPOINT_PTR_WIDTH]) && (checkpoint_head[CHECKPOINT_PTR_WIDTH-1:0] == checkpoint_tail[CHECKPOINT_PTR_WIDTH-1:0]);
    assign frat_frl_head_ptr = checkpoint_frl_head_ptr[checkpoint_tail];
endmodule
