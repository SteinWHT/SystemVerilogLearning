`timescale 1ns/1ps

module BR_DECODER
    import riscv_btb_pkg::*;
    import riscv_opcode_pkg::*;
#(
    parameter int unsigned XLEN             = 32,
    parameter int unsigned INSTR_WIDTH      = 32,
    parameter int unsigned IMEM_WIDTH       = 128,
    parameter int unsigned FETCH_INDEX_BITS = 2,

    localparam int unsigned INSTR_BYTES  = INSTR_WIDTH / 8,
    localparam int unsigned FETCH_INSTRS = IMEM_WIDTH / INSTR_WIDTH
)(
    input  logic                            packet_valid_i,
    input  logic [IMEM_WIDTH-1:0]           packet_data_i,
    input  logic [XLEN-1:0]                 packet_block_pc_i,
    input  logic [FETCH_INDEX_BITS-1:0]     packet_start_index_i,

    output logic                            decode_valid_o,
    output logic                            branch_valid_o,
    output logic [XLEN-1:0]                 branch_pc_o,
    output logic [XLEN-1:0]                 direct_target_o,
    output logic                            direct_target_valid_o,
    output btb_br_type_e                    branch_type_o
);

    logic [INSTR_WIDTH-1:0] instr;
    logic [6:0] opcode;
    logic [4:0] rd;
    logic [4:0] rs1;
    logic [2:0] funct3;
    logic [XLEN-1:0] imm_b;
    logic [XLEN-1:0] imm_j;
    logic [XLEN-1:0] instr_pc;
    logic found;

    always_comb begin
        decode_valid_o        = packet_valid_i;
        branch_valid_o        = 1'b0;
        branch_pc_o           = '0;
        direct_target_o       = '0;
        direct_target_valid_o = 1'b0;
        branch_type_o         = BTB_NONE;

        instr    = '0;
        opcode   = '0;
        rd       = '0;
        rs1      = '0;
        funct3   = '0;
        imm_b    = '0;
        imm_j    = '0;
        instr_pc = '0;
        found    = 1'b0;

        for (int i = 0; i < FETCH_INSTRS; i++) begin
            instr    = packet_data_i[i * INSTR_WIDTH +: INSTR_WIDTH];
            opcode   = instr[6:0];
            rd       = instr[11:7];
            funct3   = instr[14:12];
            rs1      = instr[19:15];
            instr_pc = packet_block_pc_i + XLEN'(i * INSTR_BYTES);

            // Immediate generation follows RISC_V_DECODER.sv.
            imm_b = {
                {(XLEN-13){instr[31]}},
                instr[31],
                instr[7],
                instr[30:25],
                instr[11:8],
                1'b0
            };
            imm_j = {
                {(XLEN-21){instr[31]}},
                instr[31],
                instr[19:12],
                instr[20],
                instr[30:21],
                1'b0
            };

            if (!found && packet_valid_i && (i >= packet_start_index_i)) begin
                unique case (opcode)
                    OP_BRANCH: begin
                        found                 = 1'b1;
                        branch_valid_o        = 1'b1;
                        branch_pc_o           = instr_pc;
                        direct_target_o       = instr_pc + imm_b;
                        direct_target_valid_o = 1'b1;
                        branch_type_o         = BTB_COND;
                    end

                    OP_JAL: begin
                        found                 = 1'b1;
                        branch_valid_o        = 1'b1;
                        branch_pc_o           = instr_pc;
                        direct_target_o       = instr_pc + imm_j;
                        direct_target_valid_o = 1'b1;

                        if (rd == 5'd1 || rd == 5'd5)
                            branch_type_o = BTB_CALL;
                        else
                            branch_type_o = BTB_JUMP;
                    end

                    OP_JALR: begin
                        if (funct3 == 3'b000) begin
                            found          = 1'b1;
                            branch_valid_o = 1'b1;
                            branch_pc_o    = instr_pc;

                            if ((rd == 5'd0) &&
                                (rs1 == 5'd1 || rs1 == 5'd5))
                                branch_type_o = BTB_RET;
                            else if (rd == 5'd1 || rd == 5'd5)
                                branch_type_o = BTB_ICALL;
                            else
                                branch_type_o = BTB_IND;
                        end
                    end

                    default: begin
                    end
                endcase
            end
        end
    end

    // synthesis translate_off
    initial begin
        assert (INSTR_WIDTH == 32)
            else $fatal(1, "BR_DECODER: only 32-bit instructions are supported");
        assert (XLEN >= 32)
            else $fatal(1, "BR_DECODER: XLEN must be at least 32");
    end
    // synthesis translate_on

endmodule
