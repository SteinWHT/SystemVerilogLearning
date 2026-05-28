// When flush is asserted, the incoming instruction will be handled by ISSUEQ
// Here we only handle the latched instructions
//
// To support MULH/MULHU/MULHSU with a single signed multiplier, inputs are
// widened to (XLEN+1) bits:
//   MUL / MULH   : sign-extend both operands   (signed x signed)
//   MULHU        : zero-extend both operands    (unsigned x unsigned)
//   MULHSU       : sign-extend A, zero-extend B (signed x unsigned)
//   MULW         : sign-extend lower 32 bits of both operands
// The multiplier uses TC=1 so the extra MSB carries the sign/zero info.
module MUL
import riscv_types_pkg::*;
#(
    parameter int unsigned XLEN = 64,
    parameter int unsigned OPCODE_WIDTH = 7,
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
    input logic                                     valid,

    // CDB interface
    input logic [ROB_INDEX_WIDTH-1:0]               cdb_flush,
    input logic [ROB_INDEX_WIDTH-1:0]               cdb_rob_depth,

    // ROB interface
    input logic [ROB_INDEX_WIDTH-1:0]               rob_top_ptr,

    output logic [ROB_INDEX_WIDTH-1:0]              exe_rob_tag,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]      exe_rd_phy_addr,
    output logic [REG_FILE_DATA_WIDTH-1:0]          exe_rd_data,
    output logic                                    exe_reg_write,
    output logic                                    exe_result_valid
);
    localparam int unsigned MUL_WIDTH = XLEN + 1; // 65-bit operands

    logic [ROB_INDEX_WIDTH-1:0]               mul_rob_tag[MUL_CYCLES];
    logic [PHY_REGISTER_FILE_WIDTH-1:0]       mul_rd_phy_addr[MUL_CYCLES];
    logic [OPCODE_WIDTH-1:0]                  mul_opcode[MUL_CYCLES];
    logic                                     mul_valid[MUL_CYCLES];
    logic                                     killed[MUL_CYCLES];
    logic [2*MUL_WIDTH-1:0]                   product; // 130-bit full product

    // Conditioned 65-bit operands
    logic [MUL_WIDTH-1:0] mul_a, mul_b;

    always_comb begin
        unique case (instr_e'(opcode))
            INSTR_MULHU: begin
                mul_a = {1'b0, rs_data_mul};
                mul_b = {1'b0, rt_data_mul};
            end
            INSTR_MULHSU: begin
                mul_a = {rs_data_mul[XLEN-1], rs_data_mul};
                mul_b = {1'b0, rt_data_mul};
            end
            INSTR_MULW: begin
                mul_a = {{(MUL_WIDTH-32){rs_data_mul[31]}}, rs_data_mul[31:0]};
                mul_b = {{(MUL_WIDTH-32){rt_data_mul[31]}}, rt_data_mul[31:0]};
            end
            default: begin // MUL, MULH
                mul_a = {rs_data_mul[XLEN-1], rs_data_mul};
                mul_b = {rt_data_mul[XLEN-1], rt_data_mul};
            end
        endcase
    end

    // Result selection based on pipelined opcode (combinational before output register)
    logic [OPCODE_WIDTH-1:0] out_opcode;
    assign out_opcode = mul_opcode[MUL_CYCLES-1];

    logic [REG_FILE_DATA_WIDTH-1:0] result_sel;
    always_comb begin
        unique case (instr_e'(out_opcode))
            INSTR_MULH, INSTR_MULHU, INSTR_MULHSU:
                result_sel = product[2*XLEN-1:XLEN]; // upper 64 bits
            INSTR_MULW:
                result_sel = {{32{product[31]}}, product[31:0]};
            default: // INSTR_MUL
                result_sel = product[XLEN-1:0]; // lower 64 bits
        endcase
    end

    always_comb begin
        for (int i = 0; i < MUL_CYCLES; i++) begin
            if (cdb_flush) begin
                killed[i] = (cdb_rob_depth < (mul_rob_tag[i] - rob_top_ptr));
            end else begin
                killed[i] = '0;
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < MUL_CYCLES; i++) begin
                mul_valid[i]        <= 1'b0;
                mul_rob_tag[i]      <= '0;
                mul_rd_phy_addr[i]  <= '0;
                mul_opcode[i]       <= '0;
            end
            exe_rd_data             <= '0;
        end else begin
            exe_rd_data         <= result_sel;
            if (valid) begin
                mul_valid[0]        <= valid;
                mul_rob_tag[0]      <= rob_tag;
                mul_rd_phy_addr[0]  <= rd_phy_addr;
                mul_opcode[0]       <= opcode;
            end else begin
                mul_valid[0]        <= '0;
                mul_rob_tag[0]      <= '0;
                mul_rd_phy_addr[0]  <= '0;
                mul_opcode[0]       <= '0;
            end

            for (int i = 1; i < MUL_CYCLES; i++) begin
                if (killed[i-1]) begin
                    mul_valid[i]    <= 1'b0;
                end else begin
                    mul_valid[i]    <= mul_valid[i-1];
                end
                mul_rob_tag[i]      <= mul_rob_tag[i-1];
                mul_rd_phy_addr[i]  <= mul_rd_phy_addr[i-1];
                mul_opcode[i]       <= mul_opcode[i-1];
            end
        end
    end

    DW02_mult_4_stage #(
        .A_width    (MUL_WIDTH),
        .B_width    (MUL_WIDTH)
    ) u_mul (
        .CLK     (clk),
        .TC      (1'b1),
        .A       (mul_a),
        .B       (mul_b),
        .PRODUCT (product)
    );

    assign exe_rob_tag = mul_rob_tag[MUL_CYCLES-1];
    assign exe_rd_phy_addr = mul_rd_phy_addr[MUL_CYCLES-1];
    assign exe_reg_write = 1'b1;
    assign exe_result_valid = mul_valid[MUL_CYCLES-1];

endmodule
