// Back-end: ISSUEQ, ISSUEUNIT, PRF, EXE, LSB, CDB.
module CPU_BACK_END #(
    parameter int unsigned XLEN                   = 64,
    parameter int unsigned INSTR_WIDTH            = 32,
    parameter int unsigned ARCH_REG_COUNT         = 32,
    parameter int unsigned ARCH_REG_WIDTH         = $clog2(ARCH_REG_COUNT),
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned REG_FILE_DATA_WIDTH    = 64,
    parameter int unsigned DMEM_WIDTH             = 32,
    parameter int unsigned DMEM_DEPTH             = 32,
    parameter int unsigned ROB_DEPTH              = 16,
    parameter int unsigned ROB_INDEX_WIDTH        = $clog2(ROB_DEPTH),
    parameter int unsigned ISSUE_QUEUE_DEPTH      = 16,
    parameter int unsigned SB_DEPTH               = 4,
    parameter int unsigned LSB_DEPTH              = 4,
    parameter int unsigned BPB_PC_BITS            = 2,
    parameter int unsigned DIV_CYCLES             = 7,
    parameter int unsigned MUL_CYCLES             = 4,
    parameter int unsigned INT_CYCLES             = 1,
    parameter int unsigned LD_ST_CYCLES           = 1,
    parameter int unsigned OPCODE_WIDTH           = 6
) (
    input logic clk,
    input logic rst_n,

    input logic [ROB_INDEX_WIDTH-1:0]           rob_top_ptr,

    // DISPATCH -> issue queues
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
    input logic [15:0]                          dis_imm16,
    input logic [DMEM_WIDTH-1:0]                dis_branch_other_addr,
    input logic [BPB_PC_BITS:0]                 dis_branch_pc_bits,
    input logic                                 dis_branch_prediction,
    input logic                                 dis_branch,
    input logic                                 dis_jr_inst,
    input logic                                 dis_jal_inst,
    input logic                                 dis_jr31_inst,

    // ROB / LSQ tag sideband
    input logic [ROB_INDEX_WIDTH-1:0]           rob_tag,
    input logic                                 rob_commit_mem_write,

    output logic [REG_FILE_DATA_WIDTH-1:0]      rt_sb_data,

    // SB -> LSQ integrated store-address buffer
    input logic [$clog2(SB_DEPTH)-1:0]          sb_flush_sw_tag,
    input logic                                 sb_flush_sw,
    input logic [$clog2(SB_DEPTH)-1:0]          sb_entry_sw_tag,
    input logic [DMEM_DEPTH-1:0]                sb_entry_sw_addr,

    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   rt_sb_phy_addr,

    // D-cache
    input logic                                 dcache_read_busy,
    input logic                                 dcache_read_done,
    input logic [REG_FILE_DATA_WIDTH-1:0]       dcache_rdata,
    output logic                                dcache_req,
    output logic [DMEM_DEPTH-1:0]               dcache_addr,

    // Issue queue occupancy (to front-end / DISPATCH)
    output logic                                issq_intq_full,
    output logic                                issq_divq_full,
    output logic                                issq_mulq_full,
    output logic                                issq_ld_stq_full,
    output logic                                issq_intq_two_or_more_vacant,
    output logic                                issq_divq_two_or_more_vacant,
    output logic                                issq_mulq_two_or_more_vacant,
    output logic                                issq_ld_stq_two_or_more_vacant,

    // CDB -> ROB / DISPATCH / front-end
    output logic                                cdb_valid,
    output logic [ROB_INDEX_WIDTH-1:0]          cdb_rob_tag,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  cdb_rd_phy_addr,
    output logic [REG_FILE_DATA_WIDTH-1:0]      cdb_rd_data,
    output logic                                cdb_reg_write,
    output logic                                cdb_flush,
    output logic [ROB_INDEX_WIDTH-1:0]          cdb_rob_depth,
    output logic [DMEM_DEPTH-1:0]               cdb_sw_addr,
    output logic                                cdb_upd_branch,
    output logic [BPB_PC_BITS-1:0]              cdb_upd_branch_addr,
    output logic                                cdb_branch_outcome,
    output logic [31:0]                         cdb_branch_addr,
    output logic                                cdb_jalr_resolved,

    // LSB -> ROB / SB (store address sideband)
    output logic [ROB_INDEX_WIDTH-1:0]          lsb_rob_tag,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  lsb_rd_phy_addr,
    output logic [REG_FILE_DATA_WIDTH-1:0]      lsb_data,
    output logic                                lsb_rw,
    output logic [DMEM_DEPTH-1:0]               lsb_sw_addr,
    output logic                                lsb_result_valid
);

    logic cdb_phy_reg_write;

    logic [PHY_REGISTER_FILE_WIDTH-1:0] prf_issue_rs_alu;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] prf_issue_rt_alu;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] prf_issue_rs_div;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] prf_issue_rt_div;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] prf_issue_rs_mul;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] prf_issue_rt_mul;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] prf_issue_rs_lsq;

    logic issue_int_rdy;
    logic issue_div_rdy;
    logic issue_mul_rdy;
    logic issue_int_grant;
    logic issue_div_grant;
    logic issue_mul_grant;
    logic exe_int_grant;
    logic exe_div_grant;
    logic exe_mul_grant;

    logic iss_lsb_ready;
    logic [OPCODE_WIDTH-1:0] iss_lsb_opcode;
    logic [ROB_INDEX_WIDTH-1:0] iss_lsb_rob_tag;
    logic [DMEM_DEPTH-1:0] iss_lsb_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_lsb_phy_addr;
    logic iss_lsb_rdy;

    logic [REG_FILE_DATA_WIDTH-1:0] iss_rs_data_lsq;

    logic issue_ld_buf;
    logic ready_ld_buf;

    logic [ROB_INDEX_WIDTH-1:0]          iss_exe_rob_tag;
    logic [OPCODE_WIDTH-1:0]             iss_exe_opcode;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]  iss_exe_rd_phy_addr;
    logic                                iss_exe_rw;
    logic [15:0]                         iss_exe_imm16;
    logic [DMEM_WIDTH-1:0]               iss_exe_branch_other_addr;
    logic                                iss_exe_branch_prediction;
    logic                                iss_exe_branch;
    logic                                iss_exe_jr_inst;
    logic                                iss_exe_jr31_inst;
    logic                                iss_exe_jal_inst;
    logic [BPB_PC_BITS-1:0]              iss_exe_branch_pc_bits;

    logic                                exe_valid;
    logic [ROB_INDEX_WIDTH-1:0]          exe_rob_tag;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]  exe_rd_phy_addr;
    logic [REG_FILE_DATA_WIDTH-1:0]      exe_rd_data;
    logic                                exe_reg_write;
    logic                                exe_branch_mispredicted;
    logic                                exe_branch;
    logic                                exe_jr_inst;
    logic                                exe_jr31_inst;
    logic                                exe_jal_inst;
    logic [BPB_PC_BITS-1:0]              exe_branch_pc_bits;
    logic [DMEM_WIDTH-1:0]               exe_branch_other_addr;

    logic [REG_FILE_DATA_WIDTH-1:0] exe_rs_data_alu;
    logic [REG_FILE_DATA_WIDTH-1:0] exe_rt_data_alu;
    logic [REG_FILE_DATA_WIDTH-1:0] exe_rs_data_div;
    logic [REG_FILE_DATA_WIDTH-1:0] exe_rt_data_div;
    logic [REG_FILE_DATA_WIDTH-1:0] exe_rs_data_mul;
    logic [REG_FILE_DATA_WIDTH-1:0] exe_rt_data_mul;

    logic div_unit_ready;
    logic div_result_valid;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] div_rd_phy_addr_wb;
    logic mul_result_valid;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] mul_rd_phy_addr_wb;

    assign cdb_phy_reg_write = cdb_reg_write & cdb_valid;

    ISSUEQ #(
        .INSTR_WIDTH(INSTR_WIDTH),
        .ISSUE_QUEUE_DEPTH(ISSUE_QUEUE_DEPTH),
        .ARCH_REG_WIDTH(ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .REG_FILE_DATA_WIDTH(REG_FILE_DATA_WIDTH),
        .DMEM_WIDTH(DMEM_WIDTH),
        .ROB_DEPTH(ROB_DEPTH),
        .DMEM_DEPTH(DMEM_DEPTH),
        .SB_DEPTH(SB_DEPTH),
        .LSB_DEPTH(LSB_DEPTH),
        .BPB_PC_BITS(BPB_PC_BITS),
        .OPCODE_WIDTH(OPCODE_WIDTH)
    ) issueq (
        .clk(clk),
        .rst_n(rst_n),
        .cdb_valid(cdb_valid),
        .cdb_flush(cdb_flush),
        .cdb_rob_depth(cdb_rob_depth),
        .cdb_rd_phy_addr(cdb_rd_phy_addr),
        .cdb_phy_reg_write(cdb_phy_reg_write),
        .iss_rs_data_lsq(iss_rs_data_lsq),
        .iss_rs_phy_addr_alu(prf_issue_rs_alu),
        .iss_rt_phy_addr_alu(prf_issue_rt_alu),
        .iss_rs_phy_addr_div(prf_issue_rs_div),
        .iss_rt_phy_addr_div(prf_issue_rt_div),
        .iss_rs_phy_addr_mul(prf_issue_rs_mul),
        .iss_rt_phy_addr_mul(prf_issue_rt_mul),
        .iss_rs_phy_addr_ls(prf_issue_rs_lsq),
        .dis_int_issq_en(dis_int_issq_en),
        .dis_div_issq_en(dis_div_issq_en),
        .dis_mul_issq_en(dis_mul_issq_en),
        .dis_ld_st_issq_en(dis_ld_st_issq_en),
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
        .dis_branch_pc_bits(dis_branch_pc_bits),
        .dis_branch_prediction(dis_branch_prediction),
        .dis_branch(dis_branch),
        .dis_jr_inst(dis_jr_inst),
        .dis_jal_inst(dis_jal_inst),
        .dis_jr31_inst(dis_jr31_inst),
        .mul_rd_phy_addr(mul_rd_phy_addr_wb),
        .mul_exe_ready(mul_result_valid),
        .div_rd_phy_addr(div_rd_phy_addr_wb),
        .div_exe_ready(div_result_valid),
        .ls_buf_rd_phy_addr(lsb_rd_phy_addr),
        .ls_buf_buf_rd_write(lsb_result_valid),
        .issq_intq_full(issq_intq_full),
        .issq_divq_full(issq_divq_full),
        .issq_mulq_full(issq_mulq_full),
        .issq_ld_stq_full(issq_ld_stq_full),
        .issq_intq_two_or_more_vacant(issq_intq_two_or_more_vacant),
        .issq_divq_two_or_more_vacant(issq_divq_two_or_more_vacant),
        .issq_mulq_two_or_more_vacant(issq_mulq_two_or_more_vacant),
        .issq_ld_stq_two_or_more_vacant(issq_ld_stq_two_or_more_vacant),
        .issue_int_en(issue_int_grant),
        .issue_div_en(issue_div_grant),
        .issue_mul_en(issue_mul_grant),
        .issue_int_rdy(issue_int_rdy),
        .issue_div_rdy(issue_div_rdy),
        .issue_mul_rdy(issue_mul_rdy),
        .exe_int_grant(exe_int_grant),
        .exe_div_grant(exe_div_grant),
        .exe_mul_grant(exe_mul_grant),
        .iss_exe_rob_tag(iss_exe_rob_tag),
        .iss_exe_opcode(iss_exe_opcode),
        .iss_exe_rd_phy_addr(iss_exe_rd_phy_addr),
        .iss_exe_rw(iss_exe_rw),
        .iss_exe_imm16(iss_exe_imm16),
        .iss_exe_branch_other_addr(iss_exe_branch_other_addr),
        .iss_exe_branch_prediction(iss_exe_branch_prediction),
        .iss_exe_branch(iss_exe_branch),
        .iss_exe_jr_inst(iss_exe_jr_inst),
        .iss_exe_jr31_inst(iss_exe_jr31_inst),
        .iss_exe_jal_inst(iss_exe_jal_inst),
        .iss_exe_branch_pc_bits(iss_exe_branch_pc_bits),
        .sb_flush_sw_tag(sb_flush_sw_tag),
        .sb_flush_sw(sb_flush_sw),
        .sb_entry_sw_tag(sb_entry_sw_tag),
        .sb_entry_sw_addr(sb_entry_sw_addr),
        .rob_tag(rob_tag),
        .rob_top_ptr(rob_top_ptr),
        .rob_commit_mem_write(rob_commit_mem_write),
        .iss_lsb_ready(iss_lsb_ready),
        .iss_lsb_opcode(iss_lsb_opcode),
        .iss_lsb_rob_tag(iss_lsb_rob_tag),
        .iss_lsb_addr(iss_lsb_addr),
        .iss_lsb_phy_addr(iss_lsb_phy_addr),
        .iss_lsb_rdy(iss_lsb_rdy),
        .dcache_read_busy(dcache_read_busy)
    );

    ISSUEUNIT #(
        .DIV_CYCLES(DIV_CYCLES),
        .MUL_CYCLES(MUL_CYCLES),
        .INT_CYCLES(INT_CYCLES),
        .LD_ST_CYCLES(LD_ST_CYCLES)
    ) issueunit (
        .clk(clk),
        .rst_n(rst_n),
        .ready_int(issue_int_rdy),
        .issue_int(issue_int_grant),
        .ready_div(issue_div_rdy),
        .div_exe_ready(div_unit_ready),
        .issue_div(issue_div_grant),
        .ready_mul(issue_mul_rdy),
        .issue_mul(issue_mul_grant),
        .ready_ld_buf(ready_ld_buf),
        .issue_ld_buf(issue_ld_buf)
    );

    EXE #(
        .XLEN(XLEN),
        .INSTR_WIDTH(INSTR_WIDTH),
        .OPCODE_WIDTH(OPCODE_WIDTH),
        .REG_FILE_DATA_WIDTH(REG_FILE_DATA_WIDTH),
        .DMEM_WIDTH(DMEM_WIDTH),
        .BPB_PC_BITS(BPB_PC_BITS),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .DIV_CYCLES(DIV_CYCLES),
        .MUL_CYCLES(MUL_CYCLES)
    ) exe (
        .clk(clk),
        .rst_n(rst_n),
        .cdb_flush(cdb_flush),
        .cdb_rob_depth(cdb_rob_depth),
        .cdb_rob_tag(cdb_rob_tag),
        .exe_valid(exe_valid),
        .exe_rob_tag(exe_rob_tag),
        .exe_rd_phy_addr(exe_rd_phy_addr),
        .exe_rd_data(exe_rd_data),
        .exe_reg_write(exe_reg_write),
        .exe_branch_mispredicted(exe_branch_mispredicted),
        .exe_branch(exe_branch),
        .exe_jr_inst(exe_jr_inst),
        .exe_jr31_inst(exe_jr31_inst),
        .exe_jal_inst(exe_jal_inst),
        .exe_branch_pc_bits(exe_branch_pc_bits),
        .exe_branch_other_addr(exe_branch_other_addr),
        .iss_rob_tag(iss_exe_rob_tag),
        .iss_opcode(iss_exe_opcode),
        .iss_rd_phy_addr(iss_exe_rd_phy_addr),
        .iss_rw(iss_exe_rw),
        .iss_imm16(iss_exe_imm16),
        .iss_branch_other_addr(iss_exe_branch_other_addr),
        .iss_branch_prediction(iss_exe_branch_prediction),
        .iss_branch(iss_exe_branch),
        .iss_jr_inst(iss_exe_jr_inst),
        .iss_jr31_inst(iss_exe_jr31_inst),
        .iss_jal_inst(iss_exe_jal_inst),
        .iss_branch_pc_bits(iss_exe_branch_pc_bits),
        .issue_int_en(exe_int_grant),
        .issue_div_en(exe_div_grant),
        .issue_mul_en(exe_mul_grant),
        .div_unit_ready(div_unit_ready),
        .div_result_valid(div_result_valid),
        .div_rd_phy_addr(div_rd_phy_addr_wb),
        .mul_result_valid(mul_result_valid),
        .mul_rd_phy_addr(mul_rd_phy_addr_wb),
        .exe_rs_data_alu(exe_rs_data_alu),
        .exe_rt_data_alu(exe_rt_data_alu),
        .exe_rs_data_div(exe_rs_data_div),
        .exe_rt_data_div(exe_rt_data_div),
        .exe_rs_data_mul(exe_rs_data_mul),
        .exe_rt_data_mul(exe_rt_data_mul)
    );

    PRF #(
        .REG_FILE_DATA_WIDTH(REG_FILE_DATA_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH)
    ) prf (
        .clk(clk),
        .rst_n(rst_n),
        .rt_sb_phy_addr(rt_sb_phy_addr),
        .rt_sb_data(rt_sb_data),
        .cdb_rd_phy_addr(cdb_rd_phy_addr),
        .cdb_rd_data(cdb_rd_data),
        .cdb_reg_write(cdb_reg_write),
        .issue_rs_phy_addr_alu(prf_issue_rs_alu),
        .issue_rt_phy_addr_alu(prf_issue_rt_alu),
        .issue_rs_phy_addr_div(prf_issue_rs_div),
        .issue_rt_phy_addr_div(prf_issue_rt_div),
        .issue_rs_phy_addr_mul(prf_issue_rs_mul),
        .issue_rt_phy_addr_mul(prf_issue_rt_mul),
        .issue_rs_phy_addr_lsq(prf_issue_rs_lsq),
        .issue_rs_data_lsq(iss_rs_data_lsq),
        .exe_rs_data_alu(exe_rs_data_alu),
        .exe_rt_data_alu(exe_rt_data_alu),
        .exe_rs_data_div(exe_rs_data_div),
        .exe_rt_data_div(exe_rt_data_div),
        .exe_rs_data_mul(exe_rs_data_mul),
        .exe_rt_data_mul(exe_rt_data_mul)
    );

    LSB #(
        .LSB_DEPTH(LSB_DEPTH),
        .DMEM_DEPTH(DMEM_DEPTH),
        .DMEM_WIDTH(REG_FILE_DATA_WIDTH),
        .ROB_DEPTH(ROB_DEPTH),
        .ARCH_REG_WIDTH(ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .REG_FILE_DATA_WIDTH(REG_FILE_DATA_WIDTH)
    ) lsb (
        .clk(clk),
        .rst_n(rst_n),
        .dcache_read_done(dcache_read_done),
        .dcache_data(dcache_rdata),
        .dcache_ready(dcache_req),
        .dcache_addr(dcache_addr),
        .iss_lsb_opcode(iss_lsb_opcode),
        .iss_lsb_rob_tag(iss_lsb_rob_tag),
        .iss_lsb_addr(iss_lsb_addr),
        .iss_lsb_phy_addr(iss_lsb_phy_addr),
        .iss_lsb_rdy(iss_lsb_rdy),
        .iss_lsb_ready(iss_lsb_ready),
        .issue_ld_buf(issue_ld_buf),
        .ready_ld_buf(ready_ld_buf),
        .cdb_flush(cdb_flush),
        .cdb_rob_depth(cdb_rob_depth),
        .lsb_rob_tag(lsb_rob_tag),
        .lsb_rd_phy_addr(lsb_rd_phy_addr),
        .lsb_data(lsb_data),
        .lsb_rw(lsb_rw),
        .lsb_sw_addr(lsb_sw_addr),
        .lsb_ready(lsb_result_valid),
        .rob_top_ptr(rob_top_ptr)
    );

    CDB #(
        .REG_FILE_DATA_WIDTH(REG_FILE_DATA_WIDTH),
        .DMEM_WIDTH(DMEM_WIDTH),
        .DMEM_DEPTH(DMEM_DEPTH),
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .ROB_DEPTH(ROB_DEPTH),
        .BPB_PC_BITS(BPB_PC_BITS)
    ) cdb (
        .clk(clk),
        .rst_n(rst_n),
        .rob_top_ptr(rob_top_ptr),
        .cdb_valid(cdb_valid),
        .cdb_rob_tag(cdb_rob_tag),
        .cdb_sw_addr(cdb_sw_addr),
        .cdb_flush(cdb_flush),
        .cdb_rd_phy_addr(cdb_rd_phy_addr),
        .cdb_rd_data(cdb_rd_data),
        .cdb_reg_write(cdb_reg_write),
        .cdb_rob_depth(cdb_rob_depth),
        .exe_valid(exe_valid),
        .exe_rob_tag(exe_rob_tag),
        .exe_rd_phy_addr(exe_rd_phy_addr),
        .exe_rd_data(exe_rd_data),
        .exe_reg_write(exe_reg_write),
        .exe_branch_mispredicted(exe_branch_mispredicted),
        .exe_branch(exe_branch),
        .exe_jr_inst(exe_jr_inst),
        .exe_jr31_inst(exe_jr31_inst),
        .exe_jal_inst(exe_jal_inst),
        .exe_branch_pc_bits(exe_branch_pc_bits),
        .exe_branch_other_addr(exe_branch_other_addr),
        .lsb_rob_tag(lsb_rob_tag),
        .lsb_rd_phy_addr(lsb_rd_phy_addr),
        .lsb_data(lsb_data),
        .lsb_rw(lsb_rw),
        .lsb_sw_addr(lsb_sw_addr),
        .lsb_ready(lsb_result_valid),
        .cdb_upd_branch(cdb_upd_branch),
        .cdb_upd_branch_addr(cdb_upd_branch_addr),
        .cdb_branch_outcome(cdb_branch_outcome),
        .cdb_branch_addr(cdb_branch_addr),
        .cdb_jalr_resolved(cdb_jalr_resolved)
    );

endmodule
