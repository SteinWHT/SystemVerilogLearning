// Front-end Register Alias Table
// 128 pyhsical register file index
// only support 2^N CHECKPOINT
module FRAT #(
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned ARCH_REG_COUNT = 32,
    parameter int unsigned ARCH_REG_WIDTH = $clog2(ARCH_REG_COUNT),
    parameter int unsigned NUM_CHECKPOINT = 8,
    parameter int unsigned CHECKPOINT_PTR_WIDTH = $clog2(NUM_CHECKPOINT)
) (
    input logic clk,
    input logic rst_n,
    
    input logic                                 is_branch,
    input logic                                 branch_mispredict,
    input logic [CHECKPOINT_PTR_WIDTH-1:0]      CFC_checkpoint_ptr,

    input logic [ARCH_REG_WIDTH-1:0]            rd_arch_address_in,
    input logic [ARCH_REG_WIDTH-1:0]            rs1_arch_address_in,
    input logic [ARCH_REG_WIDTH-1:0]            rs2_arch_address_in,

    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  rd_phy_address,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  rs1_phy_address,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  rs2_phy_address
);
    // FRAT array: maps architectural register index to physical register index
    // I don't use the circular buffer approach for FRAT
    logic [PHY_REGISTER_FILE_WIDTH-1:0] FRAT_array [0:ARCH_REG_COUNT-1];
    logic [PHY_REGISTER_FILE_WIDTH-1:0] checkpoint_FRAT_array [0:NUM_CHECKPOINT-1][0:ARCH_REG_COUNT-1];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < ARCH_REG_COUNT; i++) begin
                FRAT_array[i] <= i; // initialize
            end
        end else begin
            if (is_branch) begin
                if (branch_mispredict) begin
                    // On branch mispredict, restore the FRAT from the checkpoint
                    for (int i = 0; i < ARCH_REG_COUNT; i++) begin
                        FRAT_array[i] <= checkpoint_FRAT_array[CFC_checkpoint_ptr][i];
                    end
                end else begin
                    // On branch, create a checkpoint of the current FRAT state
                    for (int i = 0; i < ARCH_REG_COUNT; i++) begin
                        checkpoint_FRAT_array[CFC_checkpoint_ptr][i] <= FRAT_array[i];
                    end
                end
            end else begin
                // On normal instruction commit, update the FRAT with the new mapping
                FRAT_array[rd_arch_address_in] <= rd_phy_address_in;
            end
        end
    end

    assign rd_phy_address   =   FRAT_array[rd_arch_address_in];
    assign rs1_phy_address  =   FRAT_array[rs1_arch_address_in];
    assign rs2_phy_address  =   FRAT_array[rs2_arch_address_in];
endmodule