`timescale 1ns/1ps
module CPU #(
    parameter int unsigned INSTR_WIDTH             = 32,
    parameter int unsigned IMEM_DEPTH              = 64,
    parameter int unsigned IMEM_WIDTH              = 32,
    parameter int unsigned IMEM_DEPTH_WORD         = IMEM_DEPTH - 1,

    parameter int unsigned XLEN                    = 64,
    parameter int unsigned ARCH_REG_COUNT          = 32,
    parameter int unsigned ARCH_REG_WIDTH          = $clog2(ARCH_REG_COUNT),
    parameter int unsigned REG_FILE_DATA_WIDTH     = 64,

    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,

    parameter int unsigned DMEM_WIDTH              = 64,
    parameter int unsigned DMEM_DEPTH              = 32,

    parameter int unsigned BPB_PC_BITS             = 3,

    parameter int unsigned NUM_WAYS                = 4,
    parameter int unsigned IFQ_DEPTH               = 16,

    parameter int unsigned RAS_DEPTH               = 4,

    parameter int unsigned FRL_SIZE                = 128,
    parameter int unsigned FRL_PTR_WIDTH           = $clog2(FRL_SIZE),

    parameter int unsigned NUM_CHECKPOINT          = 8,

    parameter int unsigned ROB_DEPTH               = 16,
    parameter int unsigned ROB_INDEX_WIDTH         = $clog2(ROB_DEPTH),

    parameter int unsigned SB_DEPTH                = 4,
    parameter int unsigned SB_INDEX_WIDTH          = $clog2(SB_DEPTH),

    parameter int unsigned ISSUE_QUEUE_DEPTH       = 16,
    parameter int unsigned LSB_DEPTH               = 4,

    parameter int unsigned DIV_CYCLES              = 7,
    parameter int unsigned MUL_CYCLES              = 4,
    parameter int unsigned INT_CYCLES              = 1,
    parameter int unsigned LD_ST_CYCLES            = 1,

    parameter int unsigned OPCODE_WIDTH            = 6
) (
    input  logic clk,
    input  logic rst_n,

    // I-Cache interface
    input  logic                    imem_valid,
    input  logic [INSTR_WIDTH-1:0]  imem_data,
    output logic                    imem_read_rdy,
    output logic [IMEM_DEPTH-1:0]   imem_addr,

    // D-Cache read interface
    input  logic                            dcache_read_busy,
    input  logic                            dcache_read_done,
    input  logic [REG_FILE_DATA_WIDTH-1:0]  dcache_rdata,
    output logic                            dcache_req,
    output logic [DMEM_DEPTH-1:0]           dcache_addr,

    // D-Cache write interface
    input  logic                    dcache_valid,
    input  logic                    dcache_write_done,
    output logic [DMEM_DEPTH-1:0]   dcache_sw_addr,
    output logic [DMEM_WIDTH-1:0]   dcache_sw_data,
    output logic                    dcache_ready
);

    // ----------------------------------------------------------------
    // Front-end ↔ Back-end internal wires
    // ----------------------------------------------------------------

    // Issue queue status (back-end → front-end)
    logic issq_intq_full;
    logic issq_divq_full;
    logic issq_mulq_full;
    logic issq_ld_stq_full;
    logic issq_intq_two_or_more_vacant;
    logic issq_divq_two_or_more_vacant;
    logic issq_mulq_two_or_more_vacant;
    logic issq_ld_stq_two_or_more_vacant;

    // Dispatch signals (front-end → back-end)
    logic                                dis_rs_data_ready;
    logic                                dis_rt_data_ready;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]  dis_rs_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]  dis_rt_phy_addr;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]  dis_new_rd_phy_addr;
    logic                                dis_reg_write;
    logic [XLEN-1:0]                     dis_imm;
    logic [DMEM_WIDTH-1:0]               dis_branch_other_addr;
    logic                                dis_branch_prediction;
    logic                                dis_branch;
    logic [BPB_PC_BITS-1:0]              dis_branch_pc_bits;
    logic                                dis_jr_inst;
    logic                                dis_jal_inst;
    logic                                dis_jr31_inst;
    logic [OPCODE_WIDTH-1:0]             dis_opcode;
    logic                                dis_int_issue_en;
    logic                                dis_div_issue_en;
    logic                                dis_mul_issue_en;
    logic                                dis_ld_st_issue_en;

    // CDB signals (back-end → front-end)
    logic                                cdb_valid;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]  cdb_rd_phy_addr;
    logic                                cdb_reg_write;
    logic [ROB_INDEX_WIDTH-1:0]          cdb_rob_tag;
    logic [DMEM_DEPTH-1:0]               cdb_sw_addr;
    logic [IMEM_DEPTH-1:0]               cdb_branch_addr;
    logic [BPB_PC_BITS-1:0]              cdb_upd_branch_addr;
    logic                                cdb_upd_branch;
    logic                                cdb_branch_outcome;
    logic                                cdb_flush;
    logic                                cdb_jalr_resolved;
    logic [REG_FILE_DATA_WIDTH-1:0]      cdb_rd_data;
    logic [ROB_INDEX_WIDTH-1:0]          cdb_rob_depth;

    // ROB sideband (front-end → back-end)
    logic [ROB_INDEX_WIDTH-1:0]          rob_bottom_ptr;
    logic [ROB_INDEX_WIDTH-1:0]          rob_top_ptr;
    logic                                rob_commit_mem_write;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]  rob_commit_curr_phy_addr;

    // SB / SAB interface (front-end → back-end)
    logic [SB_INDEX_WIDTH-1:0]           sb_flush_sw_tag;
    logic                                sb_flush_sw;
    logic [SB_INDEX_WIDTH-1:0]           sb_entry_sw_tag;
    logic [DMEM_DEPTH-1:0]               sb_entry_sw_addr;

    // Store data path (back-end → front-end)
    logic [REG_FILE_DATA_WIDTH-1:0]      rt_sb_data;

    // LSB sideband (back-end outputs, partially used)
    logic [ROB_INDEX_WIDTH-1:0]          lsb_rob_tag;
    logic [PHY_REGISTER_FILE_WIDTH-1:0]  lsb_rd_phy_addr;
    logic [REG_FILE_DATA_WIDTH-1:0]      lsb_data;
    logic                                lsb_rw;
    logic [DMEM_DEPTH-1:0]               lsb_sw_addr;
    logic                                lsb_result_valid;

    // ----------------------------------------------------------------
    // Front-End
    // ----------------------------------------------------------------
    CPU_FRONT_END #(
        .INSTR_WIDTH             (INSTR_WIDTH),
        .IMEM_DEPTH              (IMEM_DEPTH),
        .IMEM_WIDTH              (IMEM_WIDTH),
        .IMEM_DEPTH_WORD         (IMEM_DEPTH_WORD),
        .ARCH_REG_COUNT          (ARCH_REG_COUNT),
        .ARCH_REG_WIDTH          (ARCH_REG_WIDTH),
        .REG_FILE_DATA_WIDTH     (REG_FILE_DATA_WIDTH),
        .PHY_REGISTER_FILE_WIDTH (PHY_REGISTER_FILE_WIDTH),
        .DMEM_WIDTH              (DMEM_WIDTH),
        .DMEM_DEPTH              (DMEM_DEPTH),
        .BPB_PC_BITS             (BPB_PC_BITS),
        .NUM_WAYS                (NUM_WAYS),
        .IFQ_DEPTH               (IFQ_DEPTH),
        .RAS_DEPTH               (RAS_DEPTH),
        .FRL_SIZE                (FRL_SIZE),
        .FRL_PTR_WIDTH           (FRL_PTR_WIDTH),
        .NUM_CHECKPOINT          (NUM_CHECKPOINT),
        .ROB_DEPTH               (ROB_DEPTH),
        .ROB_INDEX_WIDTH         (ROB_INDEX_WIDTH),
        .SB_DEPTH                (SB_DEPTH),
        .SB_INDEX_WIDTH          (SB_INDEX_WIDTH),
        .OPCODE_WIDTH            (OPCODE_WIDTH)
    ) front_end (
        .clk                             (clk),
        .rst_n                           (rst_n),

        // I-Cache
        .imem_valid                      (imem_valid),
        .imem_data                       (imem_data),
        .imem_read_rdy                   (imem_read_rdy),
        .imem_addr                       (imem_addr),

        // D-Cache write (SB → D-Cache)
        .dcache_valid                    (dcache_valid),
        .dcache_write_done               (dcache_write_done),
        .dcache_sw_addr                  (dcache_sw_addr),
        .dcache_sw_data                  (dcache_sw_data),
        .dcache_ready                    (dcache_ready),

        // Issue queue status from back-end
        .issue_intq_full                 (issq_intq_full),
        .issue_divq_full                 (issq_divq_full),
        .issue_mulq_full                 (issq_mulq_full),
        .issue_ld_stq_full               (issq_ld_stq_full),
        .issue_intq_two_or_more_vacant   (issq_intq_two_or_more_vacant),
        .issue_divq_two_or_more_vacant   (issq_divq_two_or_more_vacant),
        .issue_mulq_two_or_more_vacant   (issq_mulq_two_or_more_vacant),
        .issue_ld_stq_two_or_more_vacant (issq_ld_stq_two_or_more_vacant),

        // Dispatch outputs to back-end
        .dis_rs_data_ready               (dis_rs_data_ready),
        .dis_rt_data_ready               (dis_rt_data_ready),
        .dis_rs_phy_addr                 (dis_rs_phy_addr),
        .dis_rt_phy_addr                 (dis_rt_phy_addr),
        .dis_new_rd_phy_addr             (dis_new_rd_phy_addr),
        .dis_reg_write                   (dis_reg_write),
        .dis_imm                         (dis_imm),
        .dis_branch_other_addr           (dis_branch_other_addr),
        .dis_branch_prediction           (dis_branch_prediction),
        .dis_branch                      (dis_branch),
        .dis_branch_pc_bits              (dis_branch_pc_bits),
        .dis_jr_inst                     (dis_jr_inst),
        .dis_jal_inst                    (dis_jal_inst),
        .dis_jr31_inst                   (dis_jr31_inst),
        .dis_opcode                      (dis_opcode),
        .dis_int_issue_en                (dis_int_issue_en),
        .dis_div_issue_en                (dis_div_issue_en),
        .dis_mul_issue_en                (dis_mul_issue_en),
        .dis_ld_st_issue_en              (dis_ld_st_issue_en),

        // CDB from back-end
        .cdb_valid                       (cdb_valid),
        .cdb_rd_phy_addr                 (cdb_rd_phy_addr),
        .cdb_reg_write                   (cdb_reg_write),
        .cdb_rob_tag                     (cdb_rob_tag),
        .cdb_sw_addr                     (cdb_sw_addr),
        .cdb_sw_data                     (rt_sb_data),
        .cdb_branch_addr                 (cdb_branch_addr),
        .cdb_br_updt_addr                (cdb_upd_branch_addr),
        .cdb_branch                      (cdb_upd_branch),
        .cdb_branch_outcome              (cdb_branch_outcome),
        .cdb_flush                       (cdb_flush),
        .cdb_jalr_resolved               (cdb_jalr_resolved),

        // SB / SAB interface to back-end
        .sb_flush_sw_tag                 (sb_flush_sw_tag),
        .sb_flush_sw                     (sb_flush_sw),
        .sb_entry_sw_tag                 (sb_entry_sw_tag),
        .sb_entry_sw_addr                (sb_entry_sw_addr),

        // ROB sideband to back-end
        .rob_bottom_ptr_out              (rob_bottom_ptr),
        .rob_top_ptr_out                 (rob_top_ptr),
        .rob_commit_mem_write_out        (rob_commit_mem_write),
        .rob_commit_curr_phy_addr_out    (rob_commit_curr_phy_addr)
    );

    // ----------------------------------------------------------------
    // Back-End
    // ----------------------------------------------------------------
    CPU_BACK_END #(
        .XLEN                    (REG_FILE_DATA_WIDTH),
        .INSTR_WIDTH             (INSTR_WIDTH),
        .ARCH_REG_COUNT          (ARCH_REG_COUNT),
        .ARCH_REG_WIDTH          (ARCH_REG_WIDTH),
        .PHY_REGISTER_FILE_WIDTH (PHY_REGISTER_FILE_WIDTH),
        .REG_FILE_DATA_WIDTH     (REG_FILE_DATA_WIDTH),
        .DMEM_WIDTH              (DMEM_WIDTH),
        .DMEM_DEPTH              (DMEM_DEPTH),
        .IMEM_DEPTH              (IMEM_DEPTH),
        .ROB_DEPTH               (ROB_DEPTH),
        .ROB_INDEX_WIDTH         (ROB_INDEX_WIDTH),
        .ISSUE_QUEUE_DEPTH       (ISSUE_QUEUE_DEPTH),
        .SB_DEPTH                (SB_DEPTH),
        .LSB_DEPTH               (LSB_DEPTH),
        .BPB_PC_BITS             (BPB_PC_BITS),
        .DIV_CYCLES              (DIV_CYCLES),
        .MUL_CYCLES              (MUL_CYCLES),
        .INT_CYCLES              (INT_CYCLES),
        .LD_ST_CYCLES            (LD_ST_CYCLES),
        .OPCODE_WIDTH            (OPCODE_WIDTH)
    ) back_end (
        .clk                             (clk),
        .rst_n                           (rst_n),

        .rob_top_ptr                     (rob_top_ptr),

        // Dispatch from front-end
        .dis_int_issq_en                 (dis_int_issue_en),
        .dis_div_issq_en                 (dis_div_issue_en),
        .dis_mul_issq_en                 (dis_mul_issue_en),
        .dis_ld_st_issq_en               (dis_ld_st_issue_en),
        .dis_reg_write                   (dis_reg_write),
        .dis_rs_data_ready               (dis_rs_data_ready),
        .dis_rt_data_ready               (dis_rt_data_ready),
        .dis_rs_phy_addr                 (dis_rs_phy_addr),
        .dis_rt_phy_addr                 (dis_rt_phy_addr),
        .dis_new_rd_phy_addr             (dis_new_rd_phy_addr),
        .dis_rob_tag                     (rob_bottom_ptr),
        .dis_opcode                      (dis_opcode),
        .dis_imm                         (dis_imm),
        .dis_branch_other_addr           (dis_branch_other_addr[IMEM_DEPTH-1:0]),
        .dis_branch_pc_bits              ({1'b0, dis_branch_pc_bits}),
        .dis_branch_prediction           (dis_branch_prediction),
        .dis_branch                      (dis_branch),
        .dis_jr_inst                     (dis_jr_inst),
        .dis_jal_inst                    (dis_jal_inst),
        .dis_jr31_inst                   (dis_jr31_inst),

        // ROB sideband
        .rob_tag                         (rob_bottom_ptr),
        .rob_commit_mem_write            (rob_commit_mem_write),

        // Store data PRF read port
        .rt_sb_phy_addr                  (lsb_rd_phy_addr),
        .rt_sb_data                      (rt_sb_data),

        // SB / SAB
        .sb_flush_sw_tag                 (sb_flush_sw_tag),
        .sb_flush_sw                     (sb_flush_sw),
        .sb_entry_sw_tag                 (sb_entry_sw_tag),
        .sb_entry_sw_addr                (sb_entry_sw_addr),

        // D-Cache read
        .dcache_read_busy                (dcache_read_busy),
        .dcache_read_done                (dcache_read_done),
        .dcache_rdata                    (dcache_rdata),
        .dcache_req                      (dcache_req),
        .dcache_addr                     (dcache_addr),

        // Issue queue status to front-end
        .issq_intq_full                  (issq_intq_full),
        .issq_divq_full                  (issq_divq_full),
        .issq_mulq_full                  (issq_mulq_full),
        .issq_ld_stq_full                (issq_ld_stq_full),
        .issq_intq_two_or_more_vacant    (issq_intq_two_or_more_vacant),
        .issq_divq_two_or_more_vacant    (issq_divq_two_or_more_vacant),
        .issq_mulq_two_or_more_vacant    (issq_mulq_two_or_more_vacant),
        .issq_ld_stq_two_or_more_vacant  (issq_ld_stq_two_or_more_vacant),

        // CDB to front-end
        .cdb_valid                       (cdb_valid),
        .cdb_rob_tag                     (cdb_rob_tag),
        .cdb_rd_phy_addr                 (cdb_rd_phy_addr),
        .cdb_rd_data                     (cdb_rd_data),
        .cdb_reg_write                   (cdb_reg_write),
        .cdb_flush                       (cdb_flush),
        .cdb_rob_depth                   (cdb_rob_depth),
        .cdb_sw_addr                     (cdb_sw_addr),
        .cdb_upd_branch                  (cdb_upd_branch),
        .cdb_upd_branch_addr             (cdb_upd_branch_addr),
        .cdb_branch_outcome              (cdb_branch_outcome),
        .cdb_branch_addr                 (cdb_branch_addr),
        .cdb_jalr_resolved               (cdb_jalr_resolved),

        // LSB sideband
        .lsb_rob_tag                     (lsb_rob_tag),
        .lsb_rd_phy_addr                 (lsb_rd_phy_addr),
        .lsb_data                        (lsb_data),
        .lsb_rw                          (lsb_rw),
        .lsb_sw_addr                     (lsb_sw_addr),
        .lsb_result_valid                (lsb_result_valid)
    );

endmodule
