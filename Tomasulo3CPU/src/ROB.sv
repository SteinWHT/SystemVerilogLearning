// 32 entries
// ROB Entry Format for instruction:
// curr_phy         prev_phy        rd_addr         rw          mw          compl       sw_addr     total
// 6bits            6bits           5bits           1bit        1bit        1bit        32bits      64bits
// curr_phy: the current physical register index with stored data
// prev_phy: the previous physical register index with stored data
// rd_addr: the architectural address of the destination register
// rw: 1: register write for load instruction, integer and JAL instructions
// mw: 1: memory write for store instruction
// compl: 1 for completed, 0 for not completed
// sw_addr: the 32 bits of the store address
// pc: the program counter of the instruction
// trap_cause: non-zero for synchronous trap (ECALL/EBREAK/…), encodes mcause
// is_csr: 1 for CSR instruction, 0 for non-CSR instruction
// csr_addr: the address of the CSR
// csr_cmd: the command of the CSR
// mret_occur: 1 for MRET instruction
// rs1_arch: architectural register address for CSR rs1 (used for zimm and RRAT lookup)

// read ptr = top ptr -> commit from the top
// write ptr = bottom ptr -> dispatch from the bottom

module ROB
    import riscv_types_pkg::*;
#(
    parameter int unsigned ROB_DEPTH = 32,
    parameter int unsigned ROB_INDEX_WIDTH = $clog2(ROB_DEPTH),
    parameter int unsigned DMEM_WIDTH = 64,
    parameter int unsigned DMEM_DEPTH = 32,
    parameter int unsigned IMEM_DEPTH = 64,
    parameter int unsigned REG_FILE_DATA_WIDTH = 64,
    parameter int unsigned CSR_CAUSE_WIDTH = 5,
    parameter int unsigned ARCH_REG_COUNT = 32,
    parameter int unsigned ARCH_REG_WIDTH = $clog2(ARCH_REG_COUNT),
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned W_BYTE_NUM = DMEM_WIDTH / 8
) (
    input logic clk,
    input logic rst_n,

    // DISPATCH interface
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   dis_sw_rt_phy_addr,
    input logic                                 dis_inst_sw,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   dis_pre_phy_addr,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   dis_new_phy_addr,
    input logic                                 dis_inst_valid,
    input logic [ARCH_REG_WIDTH-1:0]            dis_rob_rd_arch_addr,
    input logic                                 dis_reg_write,
    input logic [IMEM_DEPTH-1:0]                dis_pc,
    input logic                                 dis_csr_inst,
    input csr_cmd_e                             dis_csr_cmd,
    input csr_addr_t                            dis_csr_addr,
    input logic                                 dis_trap_inst,
    input trap_cause_t                          dis_trap_cause,
    input logic                                 dis_mret_inst,
    input logic [ARCH_REG_WIDTH-1:0]            dis_csr_rs1_arch_addr,

    // RRAT-resolved physical register for CSR rs1 (combinational from RRAT)
    input logic [PHY_REGISTER_FILE_WIDTH-1:0]   rrat_csr_rs1_phy,

    output logic [ROB_INDEX_WIDTH-1:0]          rob_bottom_ptr,
    output logic                                rob_full,
    output logic                                rob_two_or_more_vacant,

    // CDB interface
    input logic                                 cdb_valid,
    input logic [ROB_INDEX_WIDTH-1:0]           cdb_rob_tag,
    input logic [DMEM_DEPTH-1:0]                cdb_sw_addr,
    input logic [W_BYTE_NUM-1:0]                cdb_sw_strb,
    input logic                                 cdb_flush,

    // PRF interface (store-data read at commit; reused for CSR rs1 read)
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  rt_sb_phy_addr,

    // SB interface
    input logic sb_full,
    output logic [DMEM_DEPTH-1:0]               rob_sw_addr,
    output logic [W_BYTE_NUM-1:0]               rob_sw_strb,
    output logic                                rob_commit_mem_write,

    // FRAT interface
    output logic [ROB_INDEX_WIDTH-1:0]          rob_top_ptr,
    output logic                                rob_commit,

    // RRAT interface
    output logic [ARCH_REG_WIDTH-1:0]           rob_commit_rd_arch_addr,
    output logic                                rob_reg_write,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  rob_commit_curr_phy_addr,

    // FRL interface
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  rob_commit_pre_phy_addr,

    // DISPATCH csr_stall release
    output logic                                rob_csr_committed,

    // CSR module interface (active during commit of CSR/trap/mret entries)
    output logic                                csr_commit_valid,
    output csr_addr_t                           csr_commit_addr,
    output csr_cmd_e                            csr_commit_cmd,
    output logic                                csr_commit_rs1_is_x0,
    output logic [4:0]                          csr_commit_zimm,
    output logic                                ecall_commit,
    output logic                                ebreak_commit,
    output logic                                mret_commit,
    output logic [IMEM_DEPTH-1:0]               trap_commit_pc,

    // CSR module results (from CSR combinational read)
    input  logic [REG_FILE_DATA_WIDTH-1:0]      csr_rdata,
    input  logic                                csr_redirect_valid,
    input  logic [REG_FILE_DATA_WIDTH-1:0]      csr_redirect_pc,

    // PRF write port for CSR result (old CSR value -> rd)
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  csr_wr_phy_addr,
    output logic [REG_FILE_DATA_WIDTH-1:0]      csr_wr_data,
    output logic                                csr_wr_en,

    // Trap flush: redirect front-end after ECALL/EBREAK/MRET commit
    output logic                                trap_commit_flush,
    output logic [IMEM_DEPTH-1:0]               trap_redirect_pc
);

    typedef struct packed {
        logic [PHY_REGISTER_FILE_WIDTH-1:0] curr_phy;
        logic [PHY_REGISTER_FILE_WIDTH-1:0] prev_phy;
        logic [ARCH_REG_WIDTH-1:0]          rd_addr;
        logic                               rw;
        logic                               mw;
        logic                               compl;
        logic [DMEM_DEPTH-1:0]              sw_addr;
        logic [W_BYTE_NUM-1:0]              sw_strb;
        logic [IMEM_DEPTH-1:0]              pc;
        trap_cause_t                        trap_cause;
        logic                               mret_occur;
        logic                               is_csr;
        csr_addr_t                          csr_addr;
        csr_cmd_e                           csr_cmd;
        logic [ARCH_REG_WIDTH-1:0]          rs1_arch;
    } rob_entry_t;

    rob_entry_t ROB_array [ROB_DEPTH];
    // the bottom_ptr and top_ptr are the pointers to the ROB_array
    // 5 bits for bottom_ptr and top_ptr, extra bit for overflow protection
    logic [ROB_INDEX_WIDTH:0] write_ptr, read_ptr, flush_ptr;
    logic empty, full;

    rob_entry_t head;
    assign head = ROB_array[read_ptr[ROB_INDEX_WIDTH-1:0]];

    logic enable;
    logic head_has_trap;
    assign head_has_trap = (head.trap_cause != TRAP_CAUSE_NONE);

    logic head_is_csr_or_trap;
    assign head_is_csr_or_trap = head.is_csr || head_has_trap || head.mret_occur;

    // FIFO to store the ROB entries
    // Since we need to modify the ROB entry, we need to have access to the ROB entry,
    // instead of a simple FIFO
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr <= '0;
            read_ptr <= '0;
            for (int i = 0; i < ROB_DEPTH; i++) begin
                ROB_array[i] <= '0;
            end
        end else begin
            if (dis_inst_valid && !full) begin
                if (dis_inst_sw) begin
                    ROB_array[write_ptr[ROB_INDEX_WIDTH-1:0]] <= '{
                        curr_phy:   dis_sw_rt_phy_addr,
                        prev_phy:   '0,
                        rd_addr:    '0,
                        rw:         1'b0,
                        mw:         1'b1,
                        compl:      1'b0,
                        sw_addr:    '0,
                        sw_strb:    '0,
                        pc:         dis_pc,
                        trap_cause: TRAP_CAUSE_NONE,
                        mret_occur: 1'b0,
                        is_csr:     1'b0,
                        csr_addr:   '0,
                        csr_cmd:    CSR_CMD_NONE,
                        rs1_arch:   '0
                    };
                end else if (dis_csr_inst) begin
                    ROB_array[write_ptr[ROB_INDEX_WIDTH-1:0]] <= '{
                        curr_phy:   dis_new_phy_addr,
                        prev_phy:   dis_pre_phy_addr,
                        rd_addr:    dis_rob_rd_arch_addr,
                        rw:         dis_reg_write,
                        mw:         1'b0,
                        compl:      1'b1,
                        sw_addr:    '0,
                        sw_strb:    '0,
                        pc:         dis_pc,
                        trap_cause: TRAP_CAUSE_NONE,
                        mret_occur: 1'b0,
                        is_csr:     1'b1,
                        csr_addr:   dis_csr_addr,
                        csr_cmd:    dis_csr_cmd,
                        rs1_arch:   dis_csr_rs1_arch_addr
                    };
                end else if (dis_trap_inst) begin
                    ROB_array[write_ptr[ROB_INDEX_WIDTH-1:0]] <= '{
                        curr_phy:   '0,
                        prev_phy:   '0,
                        rd_addr:    '0,
                        rw:         1'b0,
                        mw:         1'b0,
                        compl:      1'b1,
                        sw_addr:    '0,
                        sw_strb:    '0,
                        pc:         dis_pc,
                        trap_cause: dis_trap_cause,
                        mret_occur: 1'b0,
                        is_csr:     1'b0,
                        csr_addr:   '0,
                        csr_cmd:    CSR_CMD_NONE,
                        rs1_arch:   '0
                    };
                end else if (dis_mret_inst) begin
                    ROB_array[write_ptr[ROB_INDEX_WIDTH-1:0]] <= '{
                        curr_phy:   '0,
                        prev_phy:   '0,
                        rd_addr:    '0,
                        rw:         1'b0,
                        mw:         1'b0,
                        compl:      1'b1,
                        sw_addr:    '0,
                        sw_strb:    '0,
                        pc:         dis_pc,
                        trap_cause: TRAP_CAUSE_NONE,
                        mret_occur: 1'b1,
                        is_csr:     1'b0,
                        csr_addr:   '0,
                        csr_cmd:    CSR_CMD_NONE,
                        rs1_arch:   '0
                    };
                end else begin
                    ROB_array[write_ptr[ROB_INDEX_WIDTH-1:0]] <= '{
                        curr_phy:   dis_new_phy_addr,
                        prev_phy:   dis_pre_phy_addr,
                        rd_addr:    dis_rob_rd_arch_addr,
                        rw:         dis_reg_write,
                        mw:         1'b0,
                        compl:      1'b0,
                        sw_addr:    '0,
                        sw_strb:    '0,
                        pc:         dis_pc,
                        trap_cause: TRAP_CAUSE_NONE,
                        mret_occur: 1'b0,
                        is_csr:     1'b0,
                        csr_addr:   '0,
                        csr_cmd:    CSR_CMD_NONE,
                        rs1_arch:   '0
                    };
                end
                write_ptr <= write_ptr + 1;
            end

            if (enable) begin
                read_ptr <= read_ptr + 1;
            end

            if (cdb_valid) begin
                if (ROB_array[cdb_rob_tag].mw) begin
                    ROB_array[cdb_rob_tag].sw_addr <= cdb_sw_addr;
                    ROB_array[cdb_rob_tag].sw_strb <= cdb_sw_strb;
                end
                ROB_array[cdb_rob_tag].compl <= 1'b1;
            end

            if (cdb_flush) begin
                write_ptr <= flush_ptr + 1'b1;
            end

            if (trap_commit_flush) begin
                write_ptr <= read_ptr + 1'b1;
            end
        end
    end


    assign full = ((write_ptr[ROB_INDEX_WIDTH] != read_ptr[ROB_INDEX_WIDTH])
            && (write_ptr[ROB_INDEX_WIDTH-1:0] == read_ptr[ROB_INDEX_WIDTH-1:0]));
    assign empty = ((write_ptr[ROB_INDEX_WIDTH] == read_ptr[ROB_INDEX_WIDTH])
            && (write_ptr[ROB_INDEX_WIDTH-1:0] == read_ptr[ROB_INDEX_WIDTH-1:0]));

    // CDB interface
    assign rob_bottom_ptr = write_ptr[ROB_INDEX_WIDTH-1:0];
    assign rob_full = full;
    assign rob_two_or_more_vacant = ((write_ptr - read_ptr) <=
                                    (ROB_INDEX_WIDTH + 1)'(ROB_DEPTH - 2));

    // SB interface
    assign rob_sw_addr = head.sw_addr;
    assign rob_sw_strb = head.sw_strb;
    assign rob_commit_mem_write = head.mw && enable;
    assign rt_sb_phy_addr = head.is_csr ? rrat_csr_rs1_phy : head.curr_phy;

    // CFC interface
    assign rob_top_ptr = read_ptr[ROB_INDEX_WIDTH-1:0];
    assign rob_commit = enable;

    // RRAT interface
    assign rob_commit_rd_arch_addr = head.rd_addr;
    assign rob_reg_write = head.rw && enable;
    assign rob_commit_curr_phy_addr = head.is_csr ? head.curr_phy : head.curr_phy;

    // FRL interface
    assign rob_commit_pre_phy_addr = head.prev_phy;

    // DISPATCH csr_stall release
    assign rob_csr_committed = enable && head_is_csr_or_trap;

    // CSR commit-time execution signals (active combinationally at head)
    assign csr_commit_valid   = enable && head.is_csr;
    assign csr_commit_addr    = head.csr_addr;
    assign csr_commit_cmd     = head.csr_cmd;
    assign csr_commit_rs1_is_x0 = (head.rs1_arch == ARCH_REG_WIDTH'(0));
    assign csr_commit_zimm    = 5'(head.rs1_arch);

    assign ecall_commit  = enable && (head.trap_cause == TRAP_CAUSE_ECALL_M);
    assign ebreak_commit = enable && (head.trap_cause == TRAP_CAUSE_EBREAK);

    assign mret_commit   = enable && head.mret_occur;
    assign trap_commit_pc = head.pc;

    // CSR write-back to PRF for CSR instructions
    assign csr_wr_phy_addr = head.curr_phy;
    assign csr_wr_data     = csr_rdata;
    assign csr_wr_en       = enable && head.is_csr && head.rw;

    // Trap/MRET flush and redirect
    assign trap_commit_flush = enable && (head_has_trap || head.mret_occur);
    assign trap_redirect_pc  = csr_redirect_pc[IMEM_DEPTH-1:0];

    always_comb begin
        enable = 1'b0;

        flush_ptr = '0;

        // commit from the top rule:
        // 1. the ROB entry is completed
        // 2. the ROB is not empty (avoid flushing the ROB)
        // 3. MW is 0 or (MW is 1 and SB is not full)
        if (head.compl && !empty && (!head.mw || (!sb_full && head.mw))) begin
            enable = 1'b1;
        end

        flush_ptr = ((write_ptr[ROB_INDEX_WIDTH-1:0] > cdb_rob_tag) ?
        {write_ptr[ROB_INDEX_WIDTH], cdb_rob_tag} : {~write_ptr[ROB_INDEX_WIDTH], cdb_rob_tag});
    end

    // synthesis translate_off
    always @(posedge clk) begin
        if (enable && head_is_csr_or_trap) begin
            $display("[ROB-CSR-DBG] t=%0t commit ptr=%0d is_csr=%b trap_cause=%0d mret=%b rw=%b pc=0x%h",
                     $time, read_ptr[ROB_INDEX_WIDTH-1:0],
                     head.is_csr, head.trap_cause, head.mret_occur, head.rw, head.pc);
            if (head.is_csr) begin
                $display("  csr_addr=0x%h cmd=%0d rs1_arch=%0d rrat_phy=%0d",
                         head.csr_addr, head.csr_cmd, head.rs1_arch, rrat_csr_rs1_phy);
                $display("  csr_commit_valid=%b csr_rdata=0x%h csr_wr_en=%b wr_phy=%0d",
                         csr_commit_valid, csr_rdata, csr_wr_en, csr_wr_phy_addr);
            end
        end
        if (dis_inst_valid && !full && dis_csr_inst) begin
            $display("[ROB-CSR-DBG] t=%0t dispatch CSR at wptr=%0d csr_addr=0x%h cmd=%0d rw=%b rd=%0d rs1_arch=%0d",
                     $time, write_ptr[ROB_INDEX_WIDTH-1:0],
                     dis_csr_addr, dis_csr_cmd, dis_reg_write,
                     dis_rob_rd_arch_addr, dis_csr_rs1_arch_addr);
        end
    end
    // synthesis translate_on


endmodule
