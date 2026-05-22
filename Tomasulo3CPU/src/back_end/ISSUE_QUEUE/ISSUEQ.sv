module ISSUEQ
import riscv_types_pkg::*;
#(
    parameter int unsigned XLEN = 64,
    parameter int unsigned ISSUE_QUEUE_DEPTH = 16,
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned REG_FILE_DATA_WIDTH = 64,
    parameter int unsigned DMEM_DEPTH = 32,
    parameter int unsigned IMEM_DEPTH = 64,
    parameter int unsigned ROB_DEPTH = 16,
    parameter int unsigned ROB_INDEX_WIDTH = $clog2(ROB_DEPTH),
    parameter int unsigned SB_DEPTH = 4,
    parameter int unsigned SB_INDEX_WIDTH = $clog2(SB_DEPTH),
    parameter int unsigned BPB_PC_BITS = 2,
    parameter int unsigned OPCODE_WIDTH = 6
) (
    input logic clk,
    input logic rst_n,

    // CDB interface
    input logic                                 cdb_valid,
    input logic                                 cdb_flush,
    input logic [ROB_INDEX_WIDTH-1:0]           cdb_rob_depth,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   cdb_rd_phy_addr,
    input logic                                 cdb_phy_reg_write,

    // PRF interface
    input logic [REG_FILE_DATA_WIDTH-1:0]       iss_rs_data_lsq,

    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  iss_rs_phy_addr_alu,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  iss_rt_phy_addr_alu,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  iss_rs_phy_addr_div,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  iss_rt_phy_addr_div,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  iss_rs_phy_addr_mul,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  iss_rt_phy_addr_mul,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  iss_rs_phy_addr_ls,

    // DISPATCH interface
    input logic                                 dis_int_issq_en,
    input logic                                 dis_div_issq_en,
    input logic                                 dis_mul_issq_en,
    input logic                                 dis_ld_st_issq_en,
    input logic                                 dis_reg_write,
    input logic                                 dis_rs_data_ready,
    input logic                                 dis_rt_data_ready,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   dis_rs_phy_addr,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   dis_rt_phy_addr,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   dis_new_rd_phy_addr,
    input logic [ROB_INDEX_WIDTH-1:0]           dis_rob_tag,
    input logic [OPCODE_WIDTH-1:0]              dis_opcode,
    input logic [XLEN-1:0]                      dis_imm,
    input logic [IMEM_DEPTH-1:0]                dis_branch_other_addr,
    input logic [BPB_PC_BITS:0]                 dis_branch_pc_bits,
    input logic                                 dis_branch_prediction,
    input logic                                 dis_branch,
    input logic                                 dis_jr_inst,
    input logic                                 dis_jal_inst,
    input logic                                 dis_jr31_inst,

    output logic                                issq_intq_full,
    output logic                                issq_divq_full,
    output logic                                issq_mulq_full,
    output logic                                issq_ld_stq_full,
    output logic                                issq_intq_two_or_more_vacant,
    output logic                                issq_divq_two_or_more_vacant,
    output logic                                issq_mulq_two_or_more_vacant,
    output logic                                issq_ld_stq_two_or_more_vacant,


    // EXE / CDB forwarding into reservation queues
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   int_rd_phy_addr,
    input logic                                 int_exe_ready,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   mul_rd_phy_addr,
    input logic                                 mul_exe_ready,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   div_rd_phy_addr,
    input logic                                 div_exe_ready,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   ls_buf_rd_phy_addr,
    input logic                                 ls_buf_buf_rd_write,

    output logic                                exe_int_grant,
    output logic                                exe_div_grant,
    output logic                                exe_mul_grant,

    // Muxed issue metadata to EXE (one functional unit granted per cycle)
    output logic [ROB_INDEX_WIDTH-1:0]          iss_exe_rob_tag,
    output logic [OPCODE_WIDTH-1:0]             iss_exe_opcode,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  iss_exe_rd_phy_addr,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  iss_exe_rs_phy_addr,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  iss_exe_rt_phy_addr,
    output logic                                iss_exe_rw,
    output logic [XLEN-1:0]                     iss_exe_imm,
    output logic [IMEM_DEPTH-1:0]               iss_exe_branch_other_addr,
    output logic                                iss_exe_branch_prediction,
    output logic                                iss_exe_branch,
    output logic                                iss_exe_jr_inst,
    output logic                                iss_exe_jr31_inst,
    output logic                                iss_exe_jal_inst,
    output logic [BPB_PC_BITS-1:0]              iss_exe_branch_pc_bits,

    // ISSUEUNIT interface
    input logic                                 issue_int_en,
    input logic                                 issue_div_en,
    input logic                                 issue_mul_en,

    output logic                                issue_int_rdy,
    output logic                                issue_div_rdy,
    output logic                                issue_mul_rdy,

    // SB Interface
    input logic [SB_INDEX_WIDTH-1:0]            sb_flush_sw_tag,
    input logic                                 sb_flush_sw,
    input logic                                 sb_entry_sw,
    input logic [SB_INDEX_WIDTH-1:0]            sb_entry_sw_tag,
    input logic [DMEM_DEPTH-1:0]                sb_entry_sw_addr,

    // ROB Interface
    input logic [ROB_INDEX_WIDTH-1:0]           rob_tag,
    input logic [ROB_INDEX_WIDTH-1:0]           rob_top_ptr,
    input logic                                 rob_commit_mem_write,

    // LSB Interface
    input logic                                 lsb_en,

    output logic [OPCODE_WIDTH-1:0]             iss_lsb_opcode,
    output logic [ROB_INDEX_WIDTH-1:0]          iss_lsb_rob_tag,
    output logic [DMEM_DEPTH-1:0]               iss_lsb_addr,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  iss_lsb_phy_addr,
    output logic                                iss_lsb_rdy,

    // D-Cache Interface
    input logic                                 dcache_valid,

    output logic                                dcache_ready,
    output logic [DMEM_DEPTH-1:0]               dcache_addr
);

    // INTQ-only issue bus (also used for DIV/MUL wakeup)
    logic [ROB_INDEX_WIDTH-1:0]           iss_rob_tag_alu;
    logic [OPCODE_WIDTH-1:0]              iss_opcode_alu;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]   iss_rd_phy_addr_alu;
    logic                                 iss_rw_alu;
    logic [XLEN-1:0]                      iss_imm_alu;
    logic                                 iss_branch_prediction_alu;
    logic                                 iss_branch_alu;
    logic                                 iss_jr_inst_alu;
    logic                                 iss_jr31_inst_alu;
    logic                                 iss_jal_inst_alu;
    logic [BPB_PC_BITS-1:0]               iss_branch_pc_bits_alu;
    logic [IMEM_DEPTH-1:0]                iss_branch_other_addr_alu;

    // DIV / MUL issue metadata (internal until EXE is wired)
    logic [ROB_INDEX_WIDTH-1:0]           iss_rob_tag_div;
    logic [OPCODE_WIDTH-1:0]              iss_opcode_div;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]   iss_rd_phy_addr_div;
    logic                                 iss_rw_div;
    logic [ROB_INDEX_WIDTH-1:0]           iss_rob_tag_mul;
    logic [OPCODE_WIDTH-1:0]              iss_opcode_mul;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]   iss_rd_phy_addr_mul;
    logic                                 iss_rw_mul;

    // INTQ ALU destination valid for DIV/MUL operand wakeup
    logic iss_rd_reg_valid_alu;
    assign iss_rd_reg_valid_alu = exe_int_grant & iss_rw_alu;

    // INTQ
    INTQ #(
        .XLEN(XLEN),
        .INT_QUEUE_DEPTH(ISSUE_QUEUE_DEPTH),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .IMEM_DEPTH(IMEM_DEPTH),
        .BPB_PC_BITS(BPB_PC_BITS),
        .OPCODE_WIDTH(OPCODE_WIDTH)
    ) intq (
        .clk(clk),
        .rst_n(rst_n),

        .cdb_valid(cdb_valid),
        .cdb_flush(cdb_flush),
        .rob_top_ptr(rob_top_ptr),
        .cdb_rob_depth(cdb_rob_depth),
        .cdb_rd_phy_addr(cdb_rd_phy_addr),
        .cdb_phy_reg_write(cdb_phy_reg_write),

        .mul_rd_phy_addr(mul_rd_phy_addr),
        .mul_exe_ready(mul_exe_ready),
        .div_rd_phy_addr(div_rd_phy_addr),
        .div_exe_ready(div_exe_ready),
        .ls_buf_rd_phy_addr(ls_buf_rd_phy_addr),
        .ls_buf_buf_rd_write(ls_buf_buf_rd_write),

        .iss_rob_tag_alu(iss_rob_tag_alu),
        .iss_rs_phy_addr_alu(iss_rs_phy_addr_alu),
        .iss_rt_phy_addr_alu(iss_rt_phy_addr_alu),
        .iss_opcode_alu(iss_opcode_alu),
        .iss_rd_phy_addr_alu(iss_rd_phy_addr_alu),
        .iss_rw_alu(iss_rw_alu),
        .iss_imm_alu(iss_imm_alu),
        .iss_branch_prediction_alu(iss_branch_prediction_alu),
        .iss_branch_alu(iss_branch_alu),
        .iss_jr_inst_alu(iss_jr_inst_alu),
        .iss_jr31_inst_alu(iss_jr31_inst_alu),
        .iss_jal_inst_alu(iss_jal_inst_alu),
        .iss_branch_pc_bits_alu(iss_branch_pc_bits_alu),
        .iss_branch_other_addr_alu(iss_branch_other_addr_alu),

        .issue_int_en(issue_int_en),
        .issue_int_rdy(issue_int_rdy),
        .exe_int_grant(exe_int_grant),

        .dis_int_en(dis_int_issq_en),
        .dis_reg_write(dis_reg_write),
        .dis_rs_data_ready(dis_rs_data_ready),
        .dis_rt_data_ready(dis_rt_data_ready),
        .dis_rs_phy_addr(dis_rs_phy_addr),
        .dis_rt_phy_addr(dis_rt_phy_addr),
        .dis_new_rd_phy_addr(dis_new_rd_phy_addr),
        .dis_rob_tag(dis_rob_tag),
        .dis_opcode(dis_opcode),
        .dis_imm(dis_imm),
        .dis_branch_other_addr(dis_branch_other_addr),
        .dis_branch_prediction(dis_branch_prediction),
        .dis_branch(dis_branch),
        .dis_branch_pc_bits(dis_branch_pc_bits[BPB_PC_BITS-1:0]),
        .dis_jr_inst(dis_jr_inst),
        .dis_jal_inst(dis_jal_inst),
        .dis_jr31_inst(dis_jr31_inst),

        .iss_intq_full(issq_intq_full),
        .iss_intq_two_or_more_vacant(issq_intq_two_or_more_vacant)
    );

    // DIVQ
    DIVQ #(
        .DIV_QUEUE_DEPTH(ISSUE_QUEUE_DEPTH),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .OPCODE_WIDTH(OPCODE_WIDTH)
    ) divq (
        .clk(clk),
        .rst_n(rst_n),

        .cdb_valid(cdb_valid),
        .cdb_flush(cdb_flush),
        .rob_top_ptr(rob_top_ptr),
        .cdb_rob_depth(cdb_rob_depth),
        .cdb_rd_phy_addr(cdb_rd_phy_addr),
        .cdb_phy_reg_write(cdb_phy_reg_write),

        .int_rd_phy_addr(int_rd_phy_addr),
        .int_exe_ready(int_exe_ready),
        .mul_rd_phy_addr(mul_rd_phy_addr),
        .mul_exe_ready(mul_exe_ready),
        .div_rd_phy_addr(div_rd_phy_addr),
        .div_exe_ready(div_exe_ready),
        .ls_buf_rd_phy_addr(ls_buf_rd_phy_addr),
        .ls_buf_buf_rd_write(ls_buf_buf_rd_write),

        .iss_rob_tag_div(iss_rob_tag_div),
        .iss_rs_phy_addr_div(iss_rs_phy_addr_div),
        .iss_rt_phy_addr_div(iss_rt_phy_addr_div),
        .iss_opcode_div(iss_opcode_div),
        .iss_rd_phy_addr_div(iss_rd_phy_addr_div),
        .iss_rw_div(iss_rw_div),

        .issue_div_en(issue_div_en),
        .issue_div_rdy(issue_div_rdy),
        .exe_div_grant(exe_div_grant),

        .dis_div_issq_en(dis_div_issq_en),
        .dis_reg_write(dis_reg_write),
        .dis_rs_data_ready(dis_rs_data_ready),
        .dis_rt_data_ready(dis_rt_data_ready),
        .dis_rs_phy_addr(dis_rs_phy_addr),
        .dis_rt_phy_addr(dis_rt_phy_addr),
        .dis_new_rd_phy_addr(dis_new_rd_phy_addr),
        .dis_rob_tag(dis_rob_tag),
        .dis_opcode(dis_opcode),

        .divq_full(issq_divq_full),
        .iss_divq_two_or_more_vacant(issq_divq_two_or_more_vacant)
    );

    // MULQ
    MULQ #(
        .MUL_QUEUE_DEPTH(ISSUE_QUEUE_DEPTH),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .OPCODE_WIDTH(OPCODE_WIDTH)
    ) mulq (
        .clk(clk),
        .rst_n(rst_n),

        .cdb_valid(cdb_valid),
        .cdb_flush(cdb_flush),
        .rob_top_ptr(rob_top_ptr),
        .cdb_rob_depth(cdb_rob_depth),
        .cdb_rd_phy_addr(cdb_rd_phy_addr),
        .cdb_phy_reg_write(cdb_phy_reg_write),

        .int_rd_phy_addr(int_rd_phy_addr),
        .int_exe_ready(int_exe_ready),
        .mul_rd_phy_addr(mul_rd_phy_addr),
        .mul_exe_ready(mul_exe_ready),
        .div_rd_phy_addr(div_rd_phy_addr),
        .div_exe_ready(div_exe_ready),
        .ls_buf_rd_phy_addr(ls_buf_rd_phy_addr),
        .ls_buf_buf_rd_write(ls_buf_buf_rd_write),

        .iss_rob_tag_mul(iss_rob_tag_mul),
        .iss_rs_phy_addr_mul(iss_rs_phy_addr_mul),
        .iss_rt_phy_addr_mul(iss_rt_phy_addr_mul),
        .iss_opcode_mul(iss_opcode_mul),
        .iss_rd_phy_addr_mul(iss_rd_phy_addr_mul),
        .iss_rw_mul(iss_rw_mul),

        .issue_mul_en(issue_mul_en),
        .issue_mul_rdy(issue_mul_rdy),
        .exe_mul_grant(exe_mul_grant),

        .dis_mul_issq_en(dis_mul_issq_en),
        .dis_reg_write(dis_reg_write),
        .dis_rs_data_ready(dis_rs_data_ready),
        .dis_rt_data_ready(dis_rt_data_ready),
        .dis_rs_phy_addr(dis_rs_phy_addr),
        .dis_rt_phy_addr(dis_rt_phy_addr),
        .dis_new_rd_phy_addr(dis_new_rd_phy_addr),
        .dis_rob_tag(dis_rob_tag),
        .dis_opcode(dis_opcode),

        .mulq_full(issq_mulq_full),
        .iss_mulq_two_or_more_vacant(issq_mulq_two_or_more_vacant)
    );

    // LD/STQ
    LSQ #(
        .XLEN(XLEN),
        .LSQ_DEPTH(ISSUE_QUEUE_DEPTH),
        .SAB_DEPTH(),
        .DMEM_DEPTH(DMEM_DEPTH),
        .ROB_DEPTH(ROB_DEPTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .REG_FILE_DATA_WIDTH(REG_FILE_DATA_WIDTH),
        .SB_DEPTH(SB_DEPTH),
        .OPCODE_WIDTH(OPCODE_WIDTH)
    ) lsq (
        .clk(clk),
        .rst_n(rst_n),
        // --------------------------------------------------------
        // SAB part
        // --------------------------------------------------------
        .sb_flush_sw_tag(sb_flush_sw_tag),
        .sb_flush_sw(sb_flush_sw),
        .sb_entry_sw(sb_entry_sw),
        .sb_entry_sw_tag(sb_entry_sw_tag),
        .sb_entry_sw_addr(sb_entry_sw_addr),

        .rob_tag(rob_tag),
        .rob_top_ptr(rob_top_ptr),
        .rob_commit_mem_write(rob_commit_mem_write),

        // --------------------------------------------------------
        // LSQ part
        // --------------------------------------------------------
        .dis_rs_data_ready(dis_rs_data_ready),
        .dis_rs_phy_addr(dis_rs_phy_addr),
        .dis_new_rd_phy_addr(dis_new_rd_phy_addr),
        .dis_rob_tag(dis_rob_tag),
        .dis_opcode(dis_opcode),
        .dis_ld_st_issue_en(dis_ld_st_issq_en),
        .dis_imm(dis_imm),

        .lsq_ld_st_full(issq_ld_stq_full),
        .lsq_ld_st_two_or_more_vacant(issq_ld_stq_two_or_more_vacant),

        .dcache_valid(dcache_valid),
        .dcache_ready(dcache_ready),
        .dcache_addr(dcache_addr),

        .cdb_valid(cdb_valid),
        .cdb_flush(cdb_flush),
        .cdb_rob_depth(cdb_rob_depth),
        .cdb_rd_phy_addr(cdb_rd_phy_addr),
        .cdb_phy_reg_write(cdb_phy_reg_write),

        .iss_rs_data_lsq(iss_rs_data_lsq),
        .iss_rs_phy_addr_ls(iss_rs_phy_addr_ls),

        .lsb_en(lsb_en),

        .iss_lsq_opcode(iss_lsb_opcode),
        .iss_lsq_rob_tag(iss_lsb_rob_tag),
        .iss_lsq_addr(iss_lsb_addr),
        .iss_lsq_phy_addr(iss_lsb_phy_addr),
        .iss_lsq_rdy(iss_lsb_rdy)
    );

    always_comb begin
        iss_exe_rob_tag             = '0;
        iss_exe_opcode              = '0;
        iss_exe_rd_phy_addr         = '0;
        iss_exe_rs_phy_addr         = '0;
        iss_exe_rt_phy_addr         = '0;
        iss_exe_rw                  = 1'b0;
        iss_exe_imm                 = '0;
        iss_exe_branch_other_addr   = '0;
        iss_exe_branch_prediction   = 1'b0;
        iss_exe_branch              = 1'b0;
        iss_exe_jr_inst             = 1'b0;
        iss_exe_jr31_inst           = 1'b0;
        iss_exe_jal_inst            = 1'b0;
        iss_exe_branch_pc_bits      = '0;

        if (exe_int_grant) begin
            iss_exe_rob_tag             = iss_rob_tag_alu;
            iss_exe_opcode              = iss_opcode_alu;
            iss_exe_rd_phy_addr         = iss_rd_phy_addr_alu;
            iss_exe_rs_phy_addr         = iss_rs_phy_addr_alu;
            iss_exe_rt_phy_addr         = iss_rt_phy_addr_alu;
            iss_exe_rw                  = iss_rw_alu;
            iss_exe_imm                 = iss_imm_alu;
            iss_exe_branch_other_addr   = iss_branch_other_addr_alu;
            iss_exe_branch_prediction   = iss_branch_prediction_alu;
            iss_exe_branch              = iss_branch_alu;
            iss_exe_jr_inst             = iss_jr_inst_alu;
            iss_exe_jr31_inst           = iss_jr31_inst_alu;
            iss_exe_jal_inst            = iss_jal_inst_alu;
            iss_exe_branch_pc_bits      = iss_branch_pc_bits_alu;
        end else if (exe_div_grant) begin
            iss_exe_rob_tag             = iss_rob_tag_div;
            iss_exe_opcode              = iss_opcode_div;
            iss_exe_rd_phy_addr         = iss_rd_phy_addr_div;
            iss_exe_rs_phy_addr         = iss_rs_phy_addr_div;
            iss_exe_rt_phy_addr         = iss_rt_phy_addr_div;
            iss_exe_rw                  = iss_rw_div;
        end else if (exe_mul_grant) begin
            iss_exe_rob_tag             = iss_rob_tag_mul;
            iss_exe_opcode              = iss_opcode_mul;
            iss_exe_rd_phy_addr         = iss_rd_phy_addr_mul;
            iss_exe_rs_phy_addr         = iss_rs_phy_addr_mul;
            iss_exe_rt_phy_addr         = iss_rt_phy_addr_mul;
            iss_exe_rw                  = iss_rw_mul;
        end
    end

endmodule
