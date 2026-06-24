// Back-end: ISSUEQ, ISSUEUNIT, PRF, EXE, LSB, CDB.
module CPU_BACK_END #(
    parameter int unsigned XLEN                   = 64,
    parameter int unsigned INSTR_WIDTH            = 32,
    parameter int unsigned ARCH_REG_COUNT         = 32,
    parameter int unsigned ARCH_REG_WIDTH         = $clog2(ARCH_REG_COUNT),
    parameter int unsigned PHY_REG_IDX_WIDTH      = 7,
    parameter int unsigned REG_FILE_DATA_WIDTH    = 64,
    parameter int unsigned PC_WIDTH               = 64,
    parameter int unsigned DMEM_WIDTH             = 64,
    parameter int unsigned DMEM_ADDR_WIDTH        = 32,
    parameter int unsigned ROB_DEPTH              = 16,
    parameter int unsigned ROB_INDEX_WIDTH        = $clog2(ROB_DEPTH),
    parameter int unsigned ISSUE_QUEUE_DEPTH      = 8,
    parameter int unsigned SB_DEPTH               = 4,
    parameter int unsigned LSB_DEPTH              = 4,
    parameter int unsigned BPB_PC_BITS            = 2,
    parameter int unsigned DIV_CYCLES             = 64,
    parameter int unsigned MUL_CYCLES             = 4,
    parameter int unsigned INT_CYCLES             = 1,
    parameter int unsigned LD_ST_CYCLES           = 1,
    parameter int unsigned OPCODE_WIDTH           = 7,
    parameter int unsigned W_BYTE_NUM             = DMEM_WIDTH / 8
) (
    input logic clk,
    input logic rst_n,

    // Front-end ↔ back-end channels (interfaces)
    dispatch_if.consumer                        dispatch_bus,  // DISPATCH → issue queues
    cdb_if.producer                             cdb_bus,       // CDB broadcast out
    issq_status_if.producer                     issq_bus,      // issue-queue occupancy out
    rob_sideband_if.consumer                    rob_sb_bus,    // ROB pointers/commit/fence in
    sb_alloc_if.consumer                        sb_bus,        // store-buffer alloc in

    // Store-source / CSR rs1 PRF read
    input  logic [PHY_REG_IDX_WIDTH-1:0]        st_src_phy_addr,
    output logic [REG_FILE_DATA_WIDTH-1:0]      st_src_data,

    // CSR commit write port (from front-end ROB commit path)
    input  logic [PHY_REG_IDX_WIDTH-1:0]        csr_wr_phy_addr,
    input  logic [REG_FILE_DATA_WIDTH-1:0]      csr_wr_data,
    input  logic                                csr_wr_en,

    // D-Cache load port
    input  logic                                dcache_ld_ready,
    input  logic                                dcache_ld_resp_valid,
    input  logic [DMEM_WIDTH-1:0]               dcache_ld_rdata,
    output logic                                dcache_ld_valid,
    output logic                                dcache_ld_resp_ready,
    output logic [DMEM_ADDR_WIDTH-1:0]          dcache_ld_addr,

    // LSB -> ROB / SB (store address sideband)
    output logic [ROB_INDEX_WIDTH-1:0]          lsb_rob_tag,
    output logic [PHY_REG_IDX_WIDTH-1:0]        lsb_rd_phy_addr,
    output logic [REG_FILE_DATA_WIDTH-1:0]      lsb_data,
    output logic                                lsb_rw,
    output logic [DMEM_ADDR_WIDTH-1:0]          lsb_sw_addr,
    output logic                                lsb_result_valid
);

    // ============================================================
    // Boundary adapter: pack/unpack interface members <-> local nets,
    // so every sub-module instantiation below stays flat and unchanged.
    // ============================================================
    // Dispatch (dispatch_bus.consumer -> locals)
    logic dis_int_issue_en, dis_div_issue_en, dis_mul_issue_en, dis_ld_st_issue_en,
          dis_reg_write, dis_rs1_data_ready, dis_rs2_data_ready,
          dis_branch_prediction, dis_branch, dis_jr_inst, dis_jal_inst, dis_jr31_inst;
    logic [PHY_REG_IDX_WIDTH-1:0] dis_rs1_phy_addr, dis_rs2_phy_addr, dis_new_rd_phy_addr;
    logic [OPCODE_WIDTH-1:0]      dis_opcode;
    logic [XLEN-1:0]              dis_imm;
    logic [PC_WIDTH-1:0]          dis_branch_other_addr, dis_pc;
    logic [BPB_PC_BITS:0]         dis_branch_pc_bits;
    assign dis_int_issue_en      = dispatch_bus.int_issue_en;
    assign dis_div_issue_en      = dispatch_bus.div_issue_en;
    assign dis_mul_issue_en      = dispatch_bus.mul_issue_en;
    assign dis_ld_st_issue_en    = dispatch_bus.ld_st_issue_en;
    assign dis_reg_write         = dispatch_bus.reg_write;
    assign dis_rs1_data_ready    = dispatch_bus.rs1_data_ready;
    assign dis_rs2_data_ready    = dispatch_bus.rs2_data_ready;
    assign dis_rs1_phy_addr      = dispatch_bus.rs1_phy_addr;
    assign dis_rs2_phy_addr      = dispatch_bus.rs2_phy_addr;
    assign dis_new_rd_phy_addr   = dispatch_bus.new_rd_phy_addr;
    assign dis_opcode            = dispatch_bus.opcode;
    assign dis_imm               = dispatch_bus.imm;
    assign dis_branch_other_addr = dispatch_bus.branch_other_addr;
    assign dis_branch_pc_bits    = dispatch_bus.branch_pc_bits;
    assign dis_branch_prediction = dispatch_bus.branch_prediction;
    assign dis_branch            = dispatch_bus.branch;
    assign dis_jr_inst           = dispatch_bus.jr_inst;
    assign dis_jal_inst          = dispatch_bus.jal_inst;
    assign dis_jr31_inst         = dispatch_bus.jr31_inst;
    assign dis_pc                = dispatch_bus.pc;

    // ROB sideband (rob_sb_bus.consumer -> locals). dis_rob_tag and rob_tag are
    // both the ROB write pointer (kept as two distinct nets, as before).
    logic [ROB_INDEX_WIDTH-1:0] rob_top_ptr, rob_fence_tag, dis_rob_tag, rob_tag;
    logic                       rob_fence_pending, rob_commit_mem_write;
    assign rob_top_ptr          = rob_sb_bus.top_ptr;
    assign rob_fence_pending    = rob_sb_bus.fence_pending;
    assign rob_fence_tag        = rob_sb_bus.fence_tag;
    assign rob_commit_mem_write = rob_sb_bus.commit_mem_write;
    assign dis_rob_tag          = rob_sb_bus.bottom_ptr;
    assign rob_tag              = rob_sb_bus.bottom_ptr;

    // Store-buffer alloc (sb_bus.consumer -> locals)
    logic sb_flush_sw, sb_entry_sw;
    logic [$clog2(SB_DEPTH)-1:0] sb_flush_sw_tag, sb_entry_sw_tag;
    logic [ROB_INDEX_WIDTH-1:0]  sb_entry_sw_rob_tag;
    assign sb_flush_sw_tag     = sb_bus.flush_sw_tag;
    assign sb_flush_sw         = sb_bus.flush_sw;
    assign sb_entry_sw         = sb_bus.entry_sw;
    assign sb_entry_sw_tag     = sb_bus.entry_sw_tag;
    assign sb_entry_sw_rob_tag = sb_bus.entry_sw_rob_tag;

    // D-cache load handshake (external flat port <-> local nets)
    logic dcache_ready, dcache_resp_valid, dcache_valid, dcache_resp_ready;
    logic [DMEM_WIDTH-1:0]      dcache_rdata;
    logic [DMEM_ADDR_WIDTH-1:0] dcache_addr;
    assign dcache_ready         = dcache_ld_ready;
    assign dcache_resp_valid    = dcache_ld_resp_valid;
    assign dcache_rdata         = dcache_ld_rdata;
    assign dcache_ld_valid      = dcache_valid;
    assign dcache_ld_resp_ready = dcache_resp_ready;
    assign dcache_ld_addr       = dcache_addr;

    // Issue-queue status (locals -> issq_bus.producer)
    logic issq_intq_full, issq_divq_full, issq_mulq_full, issq_ld_stq_full;
    logic issq_intq_two_or_more_vacant, issq_divq_two_or_more_vacant,
          issq_mulq_two_or_more_vacant, issq_ld_stq_two_or_more_vacant;
    assign issq_bus.intq_full                 = issq_intq_full;
    assign issq_bus.divq_full                 = issq_divq_full;
    assign issq_bus.mulq_full                 = issq_mulq_full;
    assign issq_bus.ld_stq_full               = issq_ld_stq_full;
    assign issq_bus.intq_two_or_more_vacant   = issq_intq_two_or_more_vacant;
    assign issq_bus.divq_two_or_more_vacant   = issq_divq_two_or_more_vacant;
    assign issq_bus.mulq_two_or_more_vacant   = issq_mulq_two_or_more_vacant;
    assign issq_bus.ld_stq_two_or_more_vacant = issq_ld_stq_two_or_more_vacant;

    // CDB (locals -> cdb_bus.producer)
    logic cdb_valid, cdb_reg_write, cdb_flush, cdb_upd_branch, cdb_branch_outcome;
    logic [ROB_INDEX_WIDTH-1:0]   cdb_rob_tag, cdb_rob_depth;
    logic [PHY_REG_IDX_WIDTH-1:0] cdb_rd_phy_addr;
    logic [REG_FILE_DATA_WIDTH-1:0] cdb_rd_data;
    logic [DMEM_ADDR_WIDTH-1:0]   cdb_sw_addr;
    logic [W_BYTE_NUM-1:0]        cdb_sw_strb;
    logic [BPB_PC_BITS-1:0]       cdb_upd_branch_addr;
    logic [PC_WIDTH-1:0]          cdb_branch_addr;
    assign cdb_bus.valid           = cdb_valid;
    assign cdb_bus.rob_tag         = cdb_rob_tag;
    assign cdb_bus.rd_phy_addr     = cdb_rd_phy_addr;
    assign cdb_bus.rd_data         = cdb_rd_data;
    assign cdb_bus.reg_write       = cdb_reg_write;
    assign cdb_bus.flush           = cdb_flush;
    assign cdb_bus.rob_depth       = cdb_rob_depth;
    assign cdb_bus.sw_addr         = cdb_sw_addr;
    assign cdb_bus.sw_strb         = cdb_sw_strb;
    assign cdb_bus.upd_branch      = cdb_upd_branch;
    assign cdb_bus.upd_branch_addr = cdb_upd_branch_addr;
    assign cdb_bus.branch_outcome  = cdb_branch_outcome;
    assign cdb_bus.branch_addr     = cdb_branch_addr;

    logic cdb_phy_reg_write;

    logic [PHY_REG_IDX_WIDTH-1:0] prf_issue_rs1_alu;
    logic [PHY_REG_IDX_WIDTH-1:0] prf_issue_rs2_alu;
    logic [PHY_REG_IDX_WIDTH-1:0] prf_issue_rs1_div;
    logic [PHY_REG_IDX_WIDTH-1:0] prf_issue_rs2_div;
    logic [PHY_REG_IDX_WIDTH-1:0] prf_issue_rs1_mul;
    logic [PHY_REG_IDX_WIDTH-1:0] prf_issue_rs2_mul;
    logic [PHY_REG_IDX_WIDTH-1:0] prf_issue_rs1_lsq;

    logic issue_int_rdy;
    logic issue_div_rdy;
    logic issue_mul_rdy;
    logic issue_int_grant;
    logic issue_div_grant;
    logic issue_mul_grant;
    logic exe_int_grant;
    logic exe_div_grant;
    logic exe_mul_grant;

    logic lsb_en;
    logic [OPCODE_WIDTH-1:0] iss_lsb_opcode;
    logic [ROB_INDEX_WIDTH-1:0] iss_lsb_rob_tag;
    logic [DMEM_ADDR_WIDTH-1:0] iss_lsb_addr;
    logic [W_BYTE_NUM-1:0] lsb_sw_strb;
    logic [PHY_REG_IDX_WIDTH-1:0] iss_lsb_phy_addr;
    logic iss_lsb_rdy;

    logic [REG_FILE_DATA_WIDTH-1:0] iss_rs1_data_lsq;

    logic issue_ld_buf;
    logic ready_ld_buf;

    logic [ROB_INDEX_WIDTH-1:0]          iss_exe_rob_tag;
    logic [OPCODE_WIDTH-1:0]             iss_exe_opcode;
    logic [PHY_REG_IDX_WIDTH-1:0]  iss_exe_rd_phy_addr;
    logic [PHY_REG_IDX_WIDTH-1:0]  iss_exe_rs1_phy_addr;
    logic [PHY_REG_IDX_WIDTH-1:0]  iss_exe_rs2_phy_addr;
    logic                                iss_exe_rw;
    logic [XLEN-1:0]                     iss_exe_imm;
    logic [PC_WIDTH-1:0]               iss_exe_branch_other_addr;
    logic                                iss_exe_branch_prediction;
    logic                                iss_exe_branch;
    logic                                iss_exe_jr_inst;
    logic                                iss_exe_jr31_inst;
    logic                                iss_exe_jal_inst;
    logic [BPB_PC_BITS-1:0]              iss_exe_branch_pc_bits;
    logic [PC_WIDTH-1:0]               iss_exe_pc;

    logic                                exe_valid;
    logic [ROB_INDEX_WIDTH-1:0]          exe_rob_tag;
    logic [PHY_REG_IDX_WIDTH-1:0]  exe_rd_phy_addr;
    logic [REG_FILE_DATA_WIDTH-1:0]      exe_rd_data;
    logic                                exe_reg_write;
    logic                                exe_branch_mispredicted;
    logic                                exe_branch;
    logic                                exe_jr_inst;
    logic                                exe_jr31_inst;
    logic                                exe_jal_inst;
    logic [BPB_PC_BITS-1:0]              exe_branch_pc_bits;
    logic [PC_WIDTH-1:0]               exe_branch_other_addr;

    logic [REG_FILE_DATA_WIDTH-1:0] exe_rs1_data_alu;
    logic [REG_FILE_DATA_WIDTH-1:0] exe_rs2_data_alu;
    logic [REG_FILE_DATA_WIDTH-1:0] exe_rs1_data_div;
    logic [REG_FILE_DATA_WIDTH-1:0] exe_rs2_data_div;
    logic [REG_FILE_DATA_WIDTH-1:0] exe_rs1_data_mul;
    logic [REG_FILE_DATA_WIDTH-1:0] exe_rs2_data_mul;

    logic div_unit_ready;
    logic div_result_valid;
    logic [PHY_REG_IDX_WIDTH-1:0] div_rd_phy_addr_wb;
    logic mul_result_valid;
    logic [PHY_REG_IDX_WIDTH-1:0] mul_rd_phy_addr_wb;
    logic int_result_valid;
    logic [PHY_REG_IDX_WIDTH-1:0] int_rd_phy_addr_wb;

    assign cdb_phy_reg_write = cdb_reg_write & cdb_valid;

    ISSUEQ #(
        .ISSUE_QUEUE_DEPTH(ISSUE_QUEUE_DEPTH),
        .PHY_REG_IDX_WIDTH(PHY_REG_IDX_WIDTH),
        .REG_FILE_DATA_WIDTH(REG_FILE_DATA_WIDTH),
        .DMEM_ADDR_WIDTH(DMEM_ADDR_WIDTH),
        .PC_WIDTH(PC_WIDTH),
        .ROB_DEPTH(ROB_DEPTH),
        .SB_DEPTH(SB_DEPTH),
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
        .iss_rs1_data_lsq(iss_rs1_data_lsq),
        .iss_rs1_phy_addr_alu(prf_issue_rs1_alu),
        .iss_rs2_phy_addr_alu(prf_issue_rs2_alu),
        .iss_rs1_phy_addr_div(prf_issue_rs1_div),
        .iss_rs2_phy_addr_div(prf_issue_rs2_div),
        .iss_rs1_phy_addr_mul(prf_issue_rs1_mul),
        .iss_rs2_phy_addr_mul(prf_issue_rs2_mul),
        .iss_rs1_phy_addr_ls(prf_issue_rs1_lsq),
        .dis_int_issue_en(dis_int_issue_en),
        .dis_div_issue_en(dis_div_issue_en),
        .dis_mul_issue_en(dis_mul_issue_en),
        .dis_ld_st_issue_en(dis_ld_st_issue_en),
        .dis_reg_write(dis_reg_write),
        .dis_rs1_data_ready(dis_rs1_data_ready),
        .dis_rs2_data_ready(dis_rs2_data_ready),
        .dis_rs1_phy_addr(dis_rs1_phy_addr),
        .dis_rs2_phy_addr(dis_rs2_phy_addr),
        .dis_new_rd_phy_addr(dis_new_rd_phy_addr),
        .dis_rob_tag(dis_rob_tag),
        .dis_opcode(dis_opcode),
        .dis_imm(dis_imm),
        .dis_branch_other_addr(dis_branch_other_addr),
        .dis_branch_pc_bits(dis_branch_pc_bits),
        .dis_branch_prediction(dis_branch_prediction),
        .dis_branch(dis_branch),
        .dis_jr_inst(dis_jr_inst),
        .dis_jal_inst(dis_jal_inst),
        .dis_jr31_inst(dis_jr31_inst),
        .dis_pc(dis_pc),
        .int_rd_phy_addr(int_rd_phy_addr_wb),
        .int_exe_ready(int_result_valid && exe_reg_write),
        .mul_rd_phy_addr(mul_rd_phy_addr_wb),
        .mul_exe_ready(mul_result_valid && exe_reg_write),
        .div_rd_phy_addr(div_rd_phy_addr_wb),
        .div_exe_ready(div_result_valid && exe_reg_write),
        .lsb_wake_phy_addr(lsb_rd_phy_addr),
        .lsb_wake_valid(lsb_result_valid && lsb_rw),
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
        .iss_exe_rs1_phy_addr(iss_exe_rs1_phy_addr),
        .iss_exe_rs2_phy_addr(iss_exe_rs2_phy_addr),
        .iss_exe_rw(iss_exe_rw),
        .iss_exe_imm(iss_exe_imm),
        .iss_exe_branch_other_addr(iss_exe_branch_other_addr),
        .iss_exe_branch_prediction(iss_exe_branch_prediction),
        .iss_exe_branch(iss_exe_branch),
        .iss_exe_jr_inst(iss_exe_jr_inst),
        .iss_exe_jr31_inst(iss_exe_jr31_inst),
        .iss_exe_jal_inst(iss_exe_jal_inst),
        .iss_exe_branch_pc_bits(iss_exe_branch_pc_bits),
        .iss_exe_pc(iss_exe_pc),
        .sb_flush_sw_tag(sb_flush_sw_tag),
        .sb_flush_sw(sb_flush_sw),
        .sb_entry_sw(sb_entry_sw),
        .sb_entry_sw_tag(sb_entry_sw_tag),
        .sb_entry_sw_rob_tag(sb_entry_sw_rob_tag),
        .rob_tag(rob_tag),
        .rob_top_ptr(rob_top_ptr),
        .rob_fence_pending(rob_fence_pending),
        .rob_fence_tag(rob_fence_tag),
        .rob_commit_mem_write(rob_commit_mem_write),
        .lsb_en(lsb_en),
        .iss_lsb_opcode(iss_lsb_opcode),
        .iss_lsb_rob_tag(iss_lsb_rob_tag),
        .iss_lsb_addr(iss_lsb_addr),
        .iss_lsb_phy_addr(iss_lsb_phy_addr),
        .iss_lsb_rdy(iss_lsb_rdy),
        .dcache_ready(dcache_ready),
        .dcache_valid(dcache_valid),
        .dcache_addr(dcache_addr)
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
        .OPCODE_WIDTH(OPCODE_WIDTH),
        .REG_FILE_DATA_WIDTH(REG_FILE_DATA_WIDTH),
        .PC_WIDTH(PC_WIDTH),
        .BPB_PC_BITS(BPB_PC_BITS),
        .ROB_INDEX_WIDTH(ROB_INDEX_WIDTH),
        .PHY_REG_IDX_WIDTH(PHY_REG_IDX_WIDTH),
        .DIV_CYCLES(DIV_CYCLES),
        .MUL_CYCLES(MUL_CYCLES)
    ) exe (
        .clk(clk),
        .rst_n(rst_n),
        .cdb_valid(cdb_valid),
        .cdb_reg_write(cdb_reg_write),
        .cdb_flush(cdb_flush),
        .cdb_rob_depth(cdb_rob_depth),
        .cdb_rd_phy_addr(cdb_rd_phy_addr),
        .cdb_rd_data(cdb_rd_data),
        .rob_top_ptr(rob_top_ptr),
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
        .iss_rs1_phy_addr(iss_exe_rs1_phy_addr),
        .iss_rs2_phy_addr(iss_exe_rs2_phy_addr),
        .iss_rw(iss_exe_rw),
        .iss_imm(iss_exe_imm),
        .iss_branch_other_addr(iss_exe_branch_other_addr),
        .iss_branch_prediction(iss_exe_branch_prediction),
        .iss_branch(iss_exe_branch),
        .iss_jr_inst(iss_exe_jr_inst),
        .iss_jr31_inst(iss_exe_jr31_inst),
        .iss_jal_inst(iss_exe_jal_inst),
        .iss_branch_pc_bits(iss_exe_branch_pc_bits),
        .iss_pc(iss_exe_pc),
        .issue_int_en(exe_int_grant),
        .issue_div_en(exe_div_grant),
        .issue_mul_en(exe_mul_grant),
        .int_result_valid(int_result_valid),
        .int_rd_phy_addr(int_rd_phy_addr_wb),
        .div_unit_ready(div_unit_ready),
        .div_result_valid(div_result_valid),
        .div_rd_phy_addr(div_rd_phy_addr_wb),
        .mul_result_valid(mul_result_valid),
        .mul_rd_phy_addr(mul_rd_phy_addr_wb),
        .exe_rs1_data_alu(exe_rs1_data_alu),
        .exe_rs2_data_alu(exe_rs2_data_alu),
        .exe_rs1_data_div(exe_rs1_data_div),
        .exe_rs2_data_div(exe_rs2_data_div),
        .exe_rs1_data_mul(exe_rs1_data_mul),
        .exe_rs2_data_mul(exe_rs2_data_mul)
    );

    PRF #(
        .REG_FILE_DATA_WIDTH(REG_FILE_DATA_WIDTH),
        .PHY_REG_IDX_WIDTH(PHY_REG_IDX_WIDTH)
    ) prf (
        .clk(clk),
        .rst_n(rst_n),
        .st_src_phy_addr(st_src_phy_addr),
        .st_src_data(st_src_data),
        .cdb_rd_phy_addr(cdb_rd_phy_addr),
        .cdb_rd_data(cdb_rd_data),
        .cdb_reg_write(cdb_reg_write),
        .csr_wr_phy_addr(csr_wr_phy_addr),
        .csr_wr_data(csr_wr_data),
        .csr_wr_en(csr_wr_en),
        .issue_rs1_phy_addr_alu(prf_issue_rs1_alu),
        .issue_rs2_phy_addr_alu(prf_issue_rs2_alu),
        .issue_rs1_phy_addr_div(prf_issue_rs1_div),
        .issue_rs2_phy_addr_div(prf_issue_rs2_div),
        .issue_rs1_phy_addr_mul(prf_issue_rs1_mul),
        .issue_rs2_phy_addr_mul(prf_issue_rs2_mul),
        .issue_rs1_phy_addr_lsq(prf_issue_rs1_lsq),
        .issue_rs1_data_lsq(iss_rs1_data_lsq),
        .exe_rs1_data_alu(exe_rs1_data_alu),
        .exe_rs2_data_alu(exe_rs2_data_alu),
        .exe_rs1_data_div(exe_rs1_data_div),
        .exe_rs2_data_div(exe_rs2_data_div),
        .exe_rs1_data_mul(exe_rs1_data_mul),
        .exe_rs2_data_mul(exe_rs2_data_mul)
    );

    LSB #(
        .LSB_DEPTH(LSB_DEPTH),
        .DMEM_ADDR_WIDTH(DMEM_ADDR_WIDTH),
        .DMEM_WIDTH(REG_FILE_DATA_WIDTH),
        .ROB_DEPTH(ROB_DEPTH),
        .ARCH_REG_WIDTH(ARCH_REG_WIDTH),
        .PHY_REG_IDX_WIDTH(PHY_REG_IDX_WIDTH),
        .REG_FILE_DATA_WIDTH(REG_FILE_DATA_WIDTH)
    ) lsb (
        .clk(clk),
        .rst_n(rst_n),
        .dcache_data(dcache_rdata),
        .dcache_resp_valid(dcache_resp_valid),
        .dcache_resp_ready(dcache_resp_ready),
        .iss_lsb_opcode(iss_lsb_opcode),
        .iss_lsb_rob_tag(iss_lsb_rob_tag),
        .iss_lsb_addr(iss_lsb_addr),
        .iss_lsb_phy_addr(iss_lsb_phy_addr),
        .iss_lsb_rdy(iss_lsb_rdy),
        .lsb_en(lsb_en),
        .issue_ld_buf(issue_ld_buf),
        .ready_ld_buf(ready_ld_buf),
        .cdb_flush(cdb_flush),
        .cdb_rob_depth(cdb_rob_depth),
        .lsb_rob_tag(lsb_rob_tag),
        .lsb_rd_phy_addr(lsb_rd_phy_addr),
        .lsb_data(lsb_data),
        .lsb_rw(lsb_rw),
        .lsb_sw_addr(lsb_sw_addr),
        .lsb_sw_strb(lsb_sw_strb),
        .lsb_ready(lsb_result_valid),
        .rob_top_ptr(rob_top_ptr)
    );

    CDB #(
        .REG_FILE_DATA_WIDTH(REG_FILE_DATA_WIDTH),
        .DMEM_WIDTH(DMEM_WIDTH),
        .DMEM_ADDR_WIDTH(DMEM_ADDR_WIDTH),
        .PC_WIDTH(PC_WIDTH),
        .PHY_REG_IDX_WIDTH(PHY_REG_IDX_WIDTH),
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
        .cdb_sw_strb(cdb_sw_strb),
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
        .lsb_sw_strb(lsb_sw_strb),
        .lsb_ready(lsb_result_valid),
        .cdb_upd_branch(cdb_upd_branch),
        .cdb_upd_branch_addr(cdb_upd_branch_addr),
        .cdb_branch_outcome(cdb_branch_outcome),
        .cdb_branch_addr(cdb_branch_addr)
    );

endmodule
