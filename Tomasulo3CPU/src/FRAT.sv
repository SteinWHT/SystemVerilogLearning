// Front-end Register Alias Table
// 128 pyhsical register file index
// only support 2^N CHECKPOINT
module FRAT #(
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned ARCH_REG_COUNT = 32,
    parameter int unsigned ARCH_REG_WIDTH = $clog2(ARCH_REG_COUNT),
    // NUM_CHECKPOINT should be 2^N due to the round robin pointer
    parameter int unsigned NUM_CHECKPOINT = 8,
    parameter int unsigned CHECKPOINT_PTR_WIDTH = $clog2(NUM_CHECKPOINT),
    parameter int unsigned ROB_DEPTH = 32,
    parameter int unsigned ROB_INDEX_WIDTH = $clog2(ROB_DEPTH),
    parameter int unsigned FRL_SIZE = 2**PHY_REGISTER_FILE_WIDTH - ARCH_REG_COUNT,
    parameter int unsigned FRL_PTR_WIDTH = $clog2(FRL_SIZE)
) (
    input logic clk,
    input logic rst_n,

    // DISPATCH
    input logic                                 is_branch,
    input logic [ROB_INDEX_WIDTH-1:0]           rob_bottom_ptr,
    input logic                                 dis_frat_reg_write,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   rd_new_phy_address_in,
    input logic [ARCH_REG_WIDTH-1:0]            rd_new_arch_address_in,

    // COMMIT / MISPREDICT
    input logic                                 cdb_valid,
    input logic                                 branch_mispredict,
    input logic [ROB_INDEX_WIDTH-1:0]           mispredict_rob_tag,
    input logic                                 rob_commit,
    input logic [ROB_INDEX_WIDTH-1:0]           rob_top_ptr,

    // FRL interface
    input logic [FRL_PTR_WIDTH:0]               frl_head_ptr,
    output logic [FRL_PTR_WIDTH:0]              frat_frl_head_ptr,

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
    logic [PHY_REGISTER_FILE_WIDTH-1:0] frat_array [ARCH_REG_COUNT];
    logic [PHY_REGISTER_FILE_WIDTH-1:0] checkpoint_frat_array [NUM_CHECKPOINT][ARCH_REG_COUNT];

    logic [ROB_INDEX_WIDTH-1:0] checkpoint_tag_array [NUM_CHECKPOINT];
    logic [FRL_PTR_WIDTH:0] checkpoint_frl_head_ptr [NUM_CHECKPOINT];

    // round robin pointer
    logic [CHECKPOINT_PTR_WIDTH:0] checkpoint_head, checkpoint_tail;

    logic empty;

    // Parallel compare to find the checkpoint matching the mispredicting branch
    logic [CHECKPOINT_PTR_WIDTH-1:0] mispredict_slot;
    logic mispredict_found;
    logic mispredict_wrap;
    always_comb begin
        mispredict_slot  = '0;
        mispredict_found = 1'b0;
        mispredict_wrap  = 1'b0;
        for (int i = 0; i < NUM_CHECKPOINT; i++) begin
            logic [CHECKPOINT_PTR_WIDTH:0] ptr1, ptr2;
            logic [CHECKPOINT_PTR_WIDTH:0] dist1, dist2;
            logic [CHECKPOINT_PTR_WIDTH:0] max_dist;
            logic is_active1, is_active2;

            ptr1 = {checkpoint_tail[CHECKPOINT_PTR_WIDTH], CHECKPOINT_PTR_WIDTH'(i)};
            ptr2 = {~checkpoint_tail[CHECKPOINT_PTR_WIDTH], CHECKPOINT_PTR_WIDTH'(i)};

            dist1 = ptr1 - checkpoint_tail;
            dist2 = ptr2 - checkpoint_tail;
            max_dist = checkpoint_head - checkpoint_tail;

            is_active1 = (dist1 < max_dist);
            is_active2 = (dist2 < max_dist);

            if ((is_active1 || is_active2) && (checkpoint_tag_array[i] == mispredict_rob_tag)) begin
                mispredict_slot  = CHECKPOINT_PTR_WIDTH'(i);
                mispredict_found = 1'b1;
                mispredict_wrap  = is_active1 ? ptr1[CHECKPOINT_PTR_WIDTH] : ptr2[CHECKPOINT_PTR_WIDTH];
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < ARCH_REG_COUNT; i++) begin
                frat_array[i] <= (PHY_REGISTER_FILE_WIDTH)'(i);
            end

            checkpoint_head <= '0;
            checkpoint_tail <= '0;
            for (int i = 0; i < NUM_CHECKPOINT; i++) begin
                checkpoint_tag_array[i] <= '0;
            end
        end else begin
            // branch commit: free the oldest checkpoint when its branch commits
            if (!empty && rob_commit && rob_top_ptr ==
                checkpoint_tag_array[checkpoint_tail[CHECKPOINT_PTR_WIDTH-1:0]]) begin
                checkpoint_tail <= checkpoint_tail + 1;
            end

            // branch mispredict: restore from the mispredicting branch's checkpoint
            if (cdb_valid && branch_mispredict && mispredict_found) begin
                for (int i = 0; i < ARCH_REG_COUNT; i++) begin
                    frat_array[i] <= checkpoint_frat_array[mispredict_slot][i];
                end
                // Reset head to the mispredict slot: frees this checkpoint and all
                // younger ones so the next branch dispatch reuses this slot.
                checkpoint_head <= {mispredict_wrap, mispredict_slot};
            end

            // branch dispatch: create a new checkpoint
            if (is_branch && !full) begin
                checkpoint_head <= checkpoint_head + 1;
                checkpoint_tag_array[checkpoint_head[CHECKPOINT_PTR_WIDTH-1:0]] <= rob_bottom_ptr;
                checkpoint_frl_head_ptr[checkpoint_head[CHECKPOINT_PTR_WIDTH-1:0]] <= frl_head_ptr;
                for (int i = 0; i < ARCH_REG_COUNT; i++) begin
                    checkpoint_frat_array[checkpoint_head[CHECKPOINT_PTR_WIDTH-1:0]][i] <= frat_array[i];
                end
                if (dis_frat_reg_write) begin
                    checkpoint_frat_array[checkpoint_head[CHECKPOINT_PTR_WIDTH-1:0]][rd_new_arch_address_in] 
                        <= rd_new_phy_address_in;
                end
            end

            // normal instruction dispatch
            if (dis_frat_reg_write) begin
                frat_array[rd_new_arch_address_in] <= rd_new_phy_address_in;
            end
        end
    end

    assign rd_prev_phy_address  =   frat_array[rd_prev_arch_address_in];
    assign rs1_phy_address      =   frat_array[rs1_arch_address_in];
    assign rs2_phy_address      =   frat_array[rs2_arch_address_in];

    assign full = (checkpoint_head[CHECKPOINT_PTR_WIDTH] != checkpoint_tail[CHECKPOINT_PTR_WIDTH])
        && (checkpoint_head[CHECKPOINT_PTR_WIDTH-1:0] == checkpoint_tail[CHECKPOINT_PTR_WIDTH-1:0]);
    assign empty = (checkpoint_head == checkpoint_tail);
    assign frat_frl_head_ptr = (branch_mispredict && mispredict_found) ?
                                checkpoint_frl_head_ptr[mispredict_slot] :
                                frl_head_ptr;

    // synthesis translate_off
    // always_ff @(posedge clk) begin
    //     FRAT_BRANCH_RW: assert (!(dis_frat_reg_write && is_branch))
    //     else $display("FRAT: Branch instructions should not write to FRAT");
    // end
    // synthesis translate_on
endmodule
