// Back-end shell: ISSUEQ, ISSUEUNIT, PRF, LSB, and optional standalone SAB.
// DISPATCH, ROB commit/CDB, EXE completion, and D-cache are driven from outside.
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
    parameter int unsigned LD_ST_OPCODE_WIDTH     = 1,
    parameter int unsigned DIV_CYCLES             = 7,
    parameter int unsigned MUL_CYCLES             = 3,
    parameter int unsigned INT_CYCLES             = 1,
    parameter int unsigned LD_ST_CYCLES           = 1,
    parameter int unsigned OPCODE_WIDTH           = 6
) (
    input logic clk,
    input logic rst_n,

    // CDB / flush (from ROB / global CDB)
    input logic                                 cdb_flush,
    input logic [ROB_INDEX_WIDTH-1:0]           cdb_rob_depth,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   cdb_rd_phy_addr,
    input logic [REG_FILE_DATA_WIDTH-1:0]       cdb_rd_data,
    input logic                                 cdb_reg_write,
    input logic                                 cdb_phy_reg_write,

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
    input logic [2:0]                           dis_opcode,
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
    input logic [ROB_INDEX_WIDTH-1:0]           rob_top_ptr,
    input logic                                 rob_commit_mem_write,

    output logic [REG_FILE_DATA_WIDTH-1:0]      rt_sb_data,

    // SB -> LSQ / SAB (index widths follow SB_DEPTH)
    input logic [$clog2(SB_DEPTH)-1:0]           sb_flush_sw_tag,
    input logic                                 sb_flush_sw,
    input logic [$clog2(SB_DEPTH)-1:0]           sb_entry_sw_tag,
    input logic [DMEM_DEPTH-1:0]                sb_entry_sw_addr,
    input logic                                 sb_entry_sw_en,

    // Store data read port (PRF): physical register for SB
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   rt_sb_phy_addr,

    // D-cache
    input logic                                 dcache_read_busy,
    input logic                                 dcache_read_done,
    input logic [DMEM_DEPTH-1:0]                dcache_rdata,
    output logic                                dcache_req,
    output logic [DMEM_DEPTH-1:0]               dcache_addr,

    // Optional: standalone SAB visibility
    input logic                                 sab_lsq_empty,
    output logic                                sab_valid_out,

    // Issue queue occupancy (to front-end / DISPATCH)
    output logic                                issq_intq_full,
    output logic                                issq_divq_full,
    output logic                                issq_mulq_full,
    output logic                                issq_ld_stq_full,
    output logic                                issq_intq_two_or_more_vacant,
    output logic                                issq_divq_two_or_more_vacant,
    output logic                                issq_mulq_two_or_more_vacant,
    output logic                                issq_ld_stq_two_or_more_vacant,

    // PRF read data to execution (when EXE is attached)
    output logic [REG_FILE_DATA_WIDTH-1:0]      exe_rs_data_alu,
    output logic [REG_FILE_DATA_WIDTH-1:0]      exe_rt_data_alu,
    output logic [REG_FILE_DATA_WIDTH-1:0]      exe_rs_data_div,
    output logic [REG_FILE_DATA_WIDTH-1:0]      exe_rt_data_div,
    output logic [REG_FILE_DATA_WIDTH-1:0]      exe_rs_data_mul,
    output logic [REG_FILE_DATA_WIDTH-1:0]      exe_rt_data_mul,

    // LSB -> CDB / ROB side (when CDB is attached)
    output logic [ROB_INDEX_WIDTH-1:0]          lsb_rob_tag,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  lsb_rd_phy_addr,
    output logic [REG_FILE_DATA_WIDTH-1:0]      lsb_data,
    output logic                                lsb_rw,
    output logic [DMEM_DEPTH-1:0]               lsb_sw_addr,
    output logic                                lsb_result_valid,

    input logic [ROB_INDEX_WIDTH-1:0]           rob_bottom_ptr
);

    // PRF read addresses driven by ISSUEQ (same-cycle read / bypass in PRF)
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
    logic issue_ld_st_rdy;

    logic issue_int_grant;
    logic issue_div_grant;
    logic issue_mul_grant;
    logic exe_int_grant;
    logic exe_div_grant;
    logic exe_mul_grant;

    logic iss_lsb_ready;
    logic [LD_ST_OPCODE_WIDTH-1:0] iss_lsb_opcode;
    logic [ROB_INDEX_WIDTH-1:0] iss_lsb_rob_tag;
    logic [DMEM_DEPTH-1:0] iss_lsb_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_lsb_phy_addr;
    logic iss_lsb_rdy;

    logic [REG_FILE_DATA_WIDTH-1:0] iss_rs_data_lsq;

    logic issue_ld_buf;
    logic ready_ld_buf;

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
        .mul_rd_phy_addr(mul_rd_phy_addr),
        .mul_exe_ready(mul_exe_ready),
        .div_rd_phy_addr(div_rd_phy_addr),
        .div_exe_ready(div_exe_ready),
        .ls_buf_rd_phy_addr(ls_buf_rd_phy_addr),
        .ls_buf_buf_rd_write(ls_buf_buf_rd_write),
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
        .issue_ld_st_en(issue_ld_buf),
        .issue_int_rdy(issue_int_rdy),
        .issue_div_rdy(issue_div_rdy),
        .issue_mul_rdy(issue_mul_rdy),
        .issue_ld_st_rdy(issue_ld_st_rdy),
        .exe_int_grant(exe_int_grant),
        .exe_div_grant(exe_div_grant),
        .exe_mul_grant(exe_mul_grant),
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
        .div_exe_ready(div_exe_ready),
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
        .PHY_REGISTER_FILE_WIDTH(PHY_REGISTER_FILE_WIDTH)
    ) exe (
        .clk(clk),
        .rst_n(rst_n),

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

        .iss_rob_tag(dis_rob_tag),
        .iss_rs_phy_addr(dis_rs_phy_addr),
        .iss_rt_phy_addr(dis_rt_phy_addr),
        .iss_opcode(dis_opcode),
        .iss_rd_phy_addr(dis_new_rd_phy_addr),
        .iss_rw(dis_reg_write),
        .iss_imm16(dis_imm16),
        .iss_branch_other_addr(dis_branch_other_addr),
        .iss_branch_prediction(dis_branch_prediction),
        .iss_branch(dis_branch),
        .iss_jr_inst(dis_jr_inst),
        .iss_jr31_inst(dis_jr31_inst),
        .iss_jal_inst(dis_jal_inst),
        .iss_branch_pc_bits(dis_branch_pc_bits),
        .issue_int_en(exe_int_grant),
        .issue_div_en(exe_div_grant),
        .issue_mul_en(exe_mul_grant),

        .div_exe_ready(div_exe_ready),

        .exe_rs_data_alu(exe_rs_data_alu),
        .exe_rt_data_alu(exe_rt_data_alu),
        .exe_rs_data_div(exe_rs_data_div),
        .exe_rt_data_div(exe_rt_data_div),
        .exe_rs_data_mul(exe_rs_data_mul),
        .exe_rt_data_mul(exe_rt_data_mul),

        .issue_rs_data_lsq(iss_rs_data_lsq),
        .issue_rs_phy_addr_alu(prf_issue_rs_alu),
        .issue_rt_phy_addr_alu(prf_issue_rt_alu),
        .issue_rs_phy_addr_div(prf_issue_rs_div),
        .issue_rt_phy_addr_div(prf_issue_rt_div),
        .issue_rs_phy_addr_mul(prf_issue_rs_mul),
        .issue_rt_phy_addr_mul(prf_issue_rt_mul)
        
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

    SAB #(
        .SAB_DEPTH(8),
        .SB_DEPTH(SB_DEPTH),
        .DMEM_WIDTH(REG_FILE_DATA_WIDTH),
        .DMEM_DEPTH(DMEM_DEPTH),
        .ROB_DEPTH(ROB_DEPTH)
    ) sab (
        .clk(clk),
        .rst_n(rst_n),
        .sb_flush_sw_tag(sb_flush_sw_tag),
        .sb_flush_sw(sb_flush_sw),
        .sb_entry_sw_tag(sb_entry_sw_tag),
        .rob_tag(rob_tag),
        .rob_bottom_ptr(rob_bottom_ptr),
        .rob_commit_mem_write(rob_commit_mem_write),
        .lsq_empty(sab_lsq_empty),
        .valid_out(sab_valid_out)
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
