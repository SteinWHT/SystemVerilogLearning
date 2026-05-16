module ISSUEQ #(
    parameter int unsigned INSTR_WIDTH = 32,
    parameter int unsigned ISSUE_QUEUE_DEPTH = 16,
    parameter int unsigned ARCH_REG_WIDTH = 5,
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned REG_FILE_DATA_WIDTH = 64,
    parameter int unsigned DMEM_WIDTH = 32,
    parameter int unsigned ROB_DEPTH = 16,
    localparam int unsigned ROB_INDEX_WIDTH = $clog2(ROB_DEPTH),
    parameter int unsigned DMEM_DEPTH = 32,
    parameter int unsigned SB_DEPTH = 4,
    localparam int unsigned SB_INDEX_WIDTH = $clog2(SB_DEPTH),
    parameter int unsigned LSB_DEPTH = 4,
    parameter int unsigned LSB_INDEX_WIDTH = $clog2(LSB_DEPTH),
    parameter int unsigned BPB_PC_BITS = 2,
    parameter int unsigned ALU_OPCODE_WIDTH = 3,
    parameter int unsigned DIV_OPCODE_WIDTH = 3,
    parameter int unsigned MUL_OPCODE_WIDTH = 3,
    parameter int unsigned LD_ST_OPCODE_WIDTH = 1
) (
    input logic clk,
    input logic rst_n,

    // CDB interface
    input logic                                 cdb_flush,
    input logic [ROB_INDEX_WIDTH-1:0]           rob_top_ptr,
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
    input logic [2:0]                           dis_opcode,
    input logic [15:0]                          dis_imm16,
    input logic [DMEM_WIDTH-1:0]                dis_branch_other_addr,
    input logic [BPB_PC_BITS:0]                 dis_branch_pc_bits,
    input logic                                 dis_branch_prediction,
    input logic                                 dis_branch,
    input logic                                 dis_jr_inst,
    input logic                                 dis_jal_inst,
    input logic                                 dis_jr31_inst,

    // EXE / CDB forwarding into reservation queues
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   mul_rd_phy_addr,
    input logic                                 mul_exe_ready,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   div_rd_phy_addr,
    input logic                                 div_exe_ready,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   ls_buf_rd_phy_addr,
    input logic                                 ls_buf_buf_rd_write,

    output logic                                issq_intq_full,
    output logic                                issq_divq_full,
    output logic                                issq_mulq_full,
    output logic                                issq_ld_stq_full,
    output logic                                issq_intq_two_or_more_vacant,
    output logic                                issq_divq_two_or_more_vacant,
    output logic                                issq_mulq_two_or_more_vacant,
    output logic                                issq_ld_stq_two_or_more_vacant,

    // ISSUEUNIT interface
    input logic                                 issue_int_en,
    input logic                                 issue_div_en,
    input logic                                 issue_mul_en,
    input logic                                 issue_ld_st_en,

    output logic                                issue_int_rdy,
    output logic                                issue_div_rdy,
    output logic                                issue_mul_rdy,
    output logic                                issue_ld_st_rdy,

    output logic                                issue_int,
    output logic                                issue_div,
    output logic                                issue_mul,

    // SB Interface
    input logic [SB_INDEX_WIDTH-1:0]            sb_flush_sw_tag,
    input logic                                 sb_flush_sw,
    input logic [SB_INDEX_WIDTH-1:0]            sb_entry_sw_tag,
    input logic [DMEM_DEPTH-1:0]                sb_entry_sw_addr,
    input logic                                 sb_entry_sw_en,

    // ROB Interface
    input logic [ROB_INDEX_WIDTH-1:0]           rob_tag,
    input logic                                 rob_commit_mem_write,

    // LSB Interface
    input logic                                 iss_lsb_ready,

    output logic [LD_ST_OPCODE_WIDTH-1:0]       iss_lsb_opcode,
    output logic [ROB_INDEX_WIDTH-1:0]          iss_lsb_rob_tag,
    output logic [DMEM_DEPTH-1:0]               iss_lsb_addr,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  iss_lsb_phy_addr,
    output logic                                iss_lsb_rdy,

    // D-Cache Interface
    input logic                                 dcache_read_busy
);

    // INTQ-only issue bus (also used for DIV/MUL wakeup)
    logic [ROB_INDEX_WIDTH-1:0]           iss_rob_tag_alu;
    logic [2:0]                           iss_opcode_alu;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]   iss_rd_phy_addr_alu;
    logic                                 iss_rw_alu;
    logic [15:0]                          iss_imm16_alu;
    logic                                 iss_branch_prediction_alu;
    logic                                 iss_branch_alu;
    logic                                 iss_jr_inst_alu;
    logic                                 iss_jr31_inst_alu;
    logic                                 iss_jal_inst_alu;
    logic [BPB_PC_BITS-1:0]               iss_branch_pc_bits_alu;
    logic [DMEM_WIDTH-1:0]                iss_branch_other_addr_alu;

    // DIV / MUL issue metadata (internal until EXE is wired)
    logic [ROB_INDEX_WIDTH-1:0]           iss_rob_tag_div;
    logic [2:0]                           iss_opcode_div;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]   iss_rd_phy_addr_div;
    logic                                 iss_rw_div;
    logic [ROB_INDEX_WIDTH-1:0]           iss_rob_tag_mul;
    logic [2:0]                           iss_opcode_mul;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_rd_phy_addr_mul;
    logic                                 iss_rw_mul;

    // INTQ ALU destination valid for DIV/MUL operand wakeup
    logic iss_rd_reg_valid_alu;
    assign iss_rd_reg_valid_alu = issue_int & iss_rw_alu;

    // INTQ
    INTQ #(
        .INT_QUEUE_DEPTH(ISSUE_QUEUE_DEPTH),
        .INSTR_WIDTH(INSTR_WIDTH),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .ARCH_REG_WIDTH(ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .DMEM_WIDTH(DMEM_WIDTH),
        .BPB_PC_BITS(BPB_PC_BITS)
    ) intq (
        .clk(clk),
        .rst_n(rst_n),

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
        .iss_imm16_alu(iss_imm16_alu),
        .iss_branch_prediction_alu(iss_branch_prediction_alu),
        .iss_branch_alu(iss_branch_alu),
        .iss_jr_inst_alu(iss_jr_inst_alu),
        .iss_jr31_inst_alu(iss_jr31_inst_alu),
        .iss_jal_inst_alu(iss_jal_inst_alu),
        .iss_branch_pc_bits_alu(iss_branch_pc_bits_alu),
        .iss_branch_other_addr_alu(iss_branch_other_addr_alu),

        .issue_int_en(issue_int_en),
        .issue_int_rdy(issue_int_rdy),
        .issue_int(issue_int),

        .dis_int_en(dis_int_issq_en),
        .dis_reg_write(dis_reg_write),
        .dis_rs_data_ready(dis_rs_data_ready),
        .dis_rt_data_ready(dis_rt_data_ready),
        .dis_rs_phy_addr(dis_rs_phy_addr),
        .dis_rt_phy_addr(dis_rt_phy_addr),
        .dis_new_rd_phy_addr(dis_new_rd_phy_addr),
        .dis_rob_tag(dis_rob_tag),
        .dis_opcode(dis_opcode),
        .dis_imm16(dis_imm16),
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
        .INSTR_WIDTH(INSTR_WIDTH),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .ARCH_REG_WIDTH(ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .DMEM_WIDTH(DMEM_WIDTH)
    ) divq (
        .clk(clk),
        .rst_n(rst_n),

        .cdb_flush(cdb_flush),
        .rob_top_ptr(rob_top_ptr),
        .cdb_rob_depth(cdb_rob_depth),
        .cdb_rd_phy_addr(cdb_rd_phy_addr),
        .cdb_phy_reg_write(cdb_phy_reg_write),

        .iss_rd_phy_addr_alu(iss_rd_phy_addr_alu),
        .iss_rd_reg_valid_alu(iss_rd_reg_valid_alu),
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
        .issue_div(issue_div),

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
        .INSTR_WIDTH(INSTR_WIDTH),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .ARCH_REG_WIDTH(ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .DMEM_WIDTH(DMEM_WIDTH)
    ) mulq (
        .clk(clk),
        .rst_n(rst_n),

        .cdb_flush(cdb_flush),
        .rob_top_ptr(rob_top_ptr),
        .cdb_rob_depth(cdb_rob_depth),
        .cdb_rd_phy_addr(cdb_rd_phy_addr),
        .cdb_phy_reg_write(cdb_phy_reg_write),

        .iss_rd_phy_addr_alu(iss_rd_phy_addr_alu),
        .iss_rd_reg_valid_alu(iss_rd_reg_valid_alu),
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
        .issue_mul(issue_mul),

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
        .LSQ_DEPTH(ISSUE_QUEUE_DEPTH),
        .INSTR_WIDTH(INSTR_WIDTH),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .ARCH_REG_WIDTH(ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .DMEM_WIDTH(DMEM_WIDTH)
    ) lsq (
        .clk(clk),
        .rst_n(rst_n),
        // --------------------------------------------------------
        // SAB part
        // --------------------------------------------------------
        .sb_flush_sw_tag(sb_flush_sw_tag),
        .sb_flush_sw(sb_flush_sw),
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
        .dis_opcode(dis_opcode[0]),
        .dis_ld_st_issq_en(dis_ld_st_issq_en),
        .dis_imm16(dis_imm16),

        .issue_ld_st_en(issue_ld_st_en),
        .issue_ld_st_rdy(issue_ld_st_rdy),

        .lsq_ld_st_full(issq_ld_stq_full),
        .lsq_ld_st_two_or_more_vacant(issq_ld_stq_two_or_more_vacant),

        .dcache_read_busy(dcache_read_busy),

        .cdb_flush(cdb_flush),
        .cdb_rob_depth(cdb_rob_depth),
        .cdb_rd_phy_addr(cdb_rd_phy_addr),
        .cdb_phy_reg_write(cdb_phy_reg_write),
        .cdb_valid(cdb_phy_reg_write),

        .sb_entry_sw_en(sb_entry_sw_en),

        .iss_rs_data_lsq(iss_rs_data_lsq),
        .iss_rs_phy_addr_ls(iss_rs_phy_addr_ls),

        .iss_lsb_ready(iss_lsb_ready),
        .iss_lsq_opcode(iss_lsb_opcode),
        .iss_lsq_rob_tag(iss_lsb_rob_tag),
        .iss_lsq_addr(iss_lsb_addr),
        .iss_lsq_phy_addr(iss_lsb_phy_addr),
        .iss_lsq_rdy(iss_lsb_rdy)
    );

endmodule
