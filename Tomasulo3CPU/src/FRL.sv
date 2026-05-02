// Free List Register
// physical register file [0:127]
// 0-31: architectural registers
// 32-127: physical registers
// represent the pyhsical register file index [32:127]
// FRL now only supports 2^N entries
// No too small assertion
module FRL #(
    parameter int unsigned REGISTER_FILE_WIDTH = 7, // enough to index 128 registers
    parameter int unsigned ARCH_REG_COUNT = 32,
    parameter int unsigned FRL_SIZE = 2**REGISTER_FILE_WIDTH - ARCH_REG_COUNT,
    parameter int unsigned FRL_PTR_WIDTH = $clog2(FRL_SIZE)
) (
    input  logic clk,
    input  logic rst_n,
    
    input  logic [REGISTER_FILE_WIDTH - 1:0]    ROB_commit_pre_phy_address,
    input  logic                                ROB_commit,
    input  logic                                ROB_commit_reg_write,

    input  logic [FRL_PTR_WIDTH:0]              CFC_Frl_head_ptr,
    input  logic                                CDB_flush_signal,

    input  logic                                DIS_FRL_read,
    output logic [REGISTER_FILE_WIDTH - 1:0]    FRL_read_phy_address,
    output logic                                FRL_read_empty,

    output logic [FRL_PTR_WIDTH:0]              FRL_head_ptr_to_CFC
);

    logic [FRL_PTR_WIDTH:0] head_ptr, tail_ptr;
    logic empty;
    logic [REGISTER_FILE_WIDTH-1:0] FRL_array [0:FRL_SIZE-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head_ptr <= '0;
            tail_ptr <= {1'b1, {(FRL_PTR_WIDTH - 1){1'b0}}};
            for (int i = 0; i < FRL_SIZE; i++) begin
                FRL_array[i] <= ARCH_REG_COUNT + i; // initialize with physical register indices
            end
        end else begin
            if (ROB_commit && ROB_commit_reg_write) begin
                // On commit, add the freed physical register back to the free list
                FRL_array[tail_ptr[FRL_PTR_WIDTH-1:0]] <= ROB_commit_pre_phy_address;
                tail_ptr <= (tail_ptr[FRL_PTR_WIDTH-1:0] == (FRL_SIZE-1))? {~tail_ptr[FRL_PTR_WIDTH], {(FRL_PTR_WIDTH - 1){1'b0}}} : (tail_ptr + 1);
            end

            if(CDB_flush_signal) begin
                // On flush, we might need to restore the head pointer from CFC
                head_ptr <= CFC_Frl_head_ptr;
            end else if (DIS_FRL_read && !FRL_read_empty) begin
                // On read, provide the next free physical register and move head pointer
                FRL_read_phy_address <= FRL_array[head_ptr[FRL_PTR_WIDTH-1:0]];
                head_ptr <= (head_ptr[FRL_PTR_WIDTH-1:0] == (FRL_SIZE-1)) ? {~head_ptr[FRL_PTR_WIDTH], {(FRL_PTR_WIDTH - 1){1'b0}}} : (head_ptr + 1);
            end
        end
    end

assign empty = (head_ptr == tail_ptr);
assign FRL_read_empty = empty;

endmodule