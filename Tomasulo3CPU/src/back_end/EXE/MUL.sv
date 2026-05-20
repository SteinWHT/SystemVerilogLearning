// When flush is asserted, the incoming instruction will be handled by ISSUEQ
// Here we only handle the latched instructions
module MUL
import riscv_types_pkg::*;
#(
    parameter int unsigned XLEN = 64,
    parameter int unsigned OPCODE_WIDTH = 6,
    parameter int unsigned REG_FILE_DATA_WIDTH = 64,
    parameter int unsigned ROB_INDEX_WIDTH = 5,
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned MUL_CYCLES = 4
) (
    input logic clk,
    input logic rst_n,

    // PRF interface
    input logic [REG_FILE_DATA_WIDTH-1:0]           rs_data_mul,
    input logic [REG_FILE_DATA_WIDTH-1:0]           rt_data_mul,

    // ISSUEQ interface
    input logic [ROB_INDEX_WIDTH-1:0]               rob_tag,
    input logic [OPCODE_WIDTH-1:0]                  opcode,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]       rd_phy_addr,
    input logic [XLEN-1:0]                          imm,
    input logic                                     valid,

    // CDB interface
    input logic [ROB_INDEX_WIDTH-1:0]               cdb_flush,
    input logic [ROB_INDEX_WIDTH-1:0]               cdb_rob_depth,
    input logic [ROB_INDEX_WIDTH-1:0]               cdb_rob_tag,

    output logic [ROB_INDEX_WIDTH-1:0]              exe_rob_tag,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]      exe_rd_phy_addr,
    output logic [REG_FILE_DATA_WIDTH-1:0]          exe_rd_data,
    output logic                                    exe_reg_write,
    output logic                                    exe_result_valid
);
    localparam int unsigned MulXLen = XLEN / 2;

    logic [ROB_INDEX_WIDTH-1:0]               mul_rob_tag[MUL_CYCLES];
    logic [PHY_REGISTER_FILE_WIDTH-1:0]       mul_rd_phy_addr[MUL_CYCLES];
    logic                                     mul_valid[MUL_CYCLES];
    logic                                     killed[MUL_CYCLES];
    logic [XLEN-1:0]                          product;

    always_comb begin
        for (int i = 0; i < MUL_CYCLES; i++) begin
            if (cdb_flush) begin
                killed[i] = (cdb_rob_depth < (mul_rob_tag[i] - cdb_rob_tag));
            end else begin
                killed [i] = '0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < MUL_CYCLES; i++) begin
                mul_valid[i]        <= 1'b0;
                mul_rob_tag[i]      <= '0;
                mul_rd_phy_addr[i]  <= '0;
            end
            exe_rd_data             <= '0;
        end else begin
            exe_rd_data         <= product;
            if (valid) begin
                mul_valid[0]        <= valid;
                mul_rob_tag[0]      <= rob_tag;
                mul_rd_phy_addr[0]  <= rd_phy_addr;
            end else begin
                mul_valid[0]        <= '0;
                mul_rob_tag[0]      <= '0;
                mul_rd_phy_addr[0]  <= '0;
            end

            for (int i = 1; i < MUL_CYCLES; i++) begin
                if (killed[i-1]) begin
                    mul_valid[i]    <= 1'b0;
                end else begin
                    mul_valid[i]    <= mul_valid[i-1];
                end
                mul_rob_tag[i]      <= mul_rob_tag[i-1];
                mul_rd_phy_addr[i]  <= mul_rd_phy_addr[i-1];
            end
        end
    end

    DW02_mult_4_stage #(
        .A_width    (MulXLen),
        .B_width    (MulXLen)
    ) u_mul (
        .CLK     (clk),
        .TC      (1'b0),
        .A       (rs_data_mul[MulXLen-1:0]),
        .B       (rt_data_mul[MulXLen-1:0]),
        .PRODUCT (product)
    );

    assign exe_rob_tag = mul_rob_tag[MUL_CYCLES-1];
    assign exe_rd_phy_addr = mul_rd_phy_addr[MUL_CYCLES-1];
    assign exe_reg_write = 1'b1;
    assign exe_result_valid = mul_valid[MUL_CYCLES-1];


endmodule
