// 32 entries
// ROB Entry Format for instruction:
// curr_phy, prev_phy, rd_addr, rw, opclass, completed, store metadata,
// PC, and CSR/trap metadata are stored per entry.
// curr_phy: the current physical register index with stored data
// prev_phy: the previous physical register index with stored data
// rd_addr: the architectural address of the destination register
// rw: 1: register write for load instruction, integer and JAL instructions
// opclass: commit-time instruction behavior
// compl: 1 for completed, 0 for not completed
// sw_addr: the 32 bits of the store address
// pc: the program counter of the instruction
// trap_cause: non-zero for synchronous trap (ECALL/EBREAK/…), encodes mcause
// csr_addr: the address of the CSR
// csr_cmd: the command of the CSR
// rs1_arch: architectural register address for CSR rs1 (used for zimm and RRAT lookup)

// read ptr = top ptr -> commit from the top
// write ptr = bottom ptr -> dispatch from the bottom

module ROB
    import riscv_types_pkg::*;
#(
    parameter int unsigned ROB_DEPTH = 32,
    parameter int unsigned ROB_INDEX_WIDTH = $clog2(ROB_DEPTH),
    parameter int unsigned DMEM_WIDTH = 64,
    parameter int unsigned DMEM_ADDR_WIDTH = 32,
    parameter int unsigned PC_WIDTH = 64,
    parameter int unsigned REG_FILE_DATA_WIDTH = 64,
    parameter int unsigned CSR_CAUSE_WIDTH = 5,
    parameter int unsigned ARCH_REG_COUNT = 32,
    parameter int unsigned ARCH_REG_WIDTH = $clog2(ARCH_REG_COUNT),
    parameter int unsigned PHY_REG_IDX_WIDTH = 7,
    parameter int unsigned W_BYTE_NUM = DMEM_WIDTH / 8,
    // When set, FENCE.I commit is held until the external cache-coherence
    // controller reports the I$/D$ have been synchronized (D$ cleaned to
    // memory, I$ invalidated). Disabled by default so unit testbenches and
    // non-coherent systems keep their original single-cycle FENCE.I commit.
    parameter bit FENCE_I_COHERENCE = 1'b0
) (
    input logic clk,
    input logic rst_n,

    // DISPATCH interface
    input logic [PHY_REG_IDX_WIDTH-1:0]         dis_sw_rs2_phy_addr,
    input logic [PHY_REG_IDX_WIDTH-1:0]         dis_pre_phy_addr,
    input logic [PHY_REG_IDX_WIDTH-1:0]         dis_new_phy_addr,
    input logic                                 dis_inst_valid,
    input logic [ARCH_REG_WIDTH-1:0]            dis_rob_rd_arch_addr,
    input logic                                 dis_reg_write,
    input logic [PC_WIDTH-1:0]                  dis_pc,
    input rob_opclass_t                         dis_rob_opclass,
    input csr_cmd_e                             dis_csr_cmd,
    input csr_addr_t                            dis_csr_addr,
    input trap_cause_t                          dis_trap_cause,
    input logic [ARCH_REG_WIDTH-1:0]            dis_csr_rs1_arch_addr,

    // RRAT-resolved physical register for CSR rs1 (combinational from RRAT)
    input logic [PHY_REG_IDX_WIDTH-1:0]         rrat_csr_rs1_phy,

    output logic [ROB_INDEX_WIDTH-1:0]          rob_bottom_ptr,
    output logic                                rob_full,
    output logic                                rob_two_or_more_vacant,

    // CDB interface
    input logic                                 cdb_valid,
    input logic [ROB_INDEX_WIDTH-1:0]           cdb_rob_tag,
    input logic [DMEM_ADDR_WIDTH-1:0]           cdb_sw_addr,
    input logic [W_BYTE_NUM-1:0]                cdb_sw_strb,
    input logic                                 cdb_flush,

    // PRF interface (store-data read at commit; reused for CSR rs1 read)
    output logic [PHY_REG_IDX_WIDTH-1:0]        st_src_phy_addr,

    // SB interface
    input logic sb_full,
    input logic sb_drained,
    output logic [DMEM_ADDR_WIDTH-1:0]          rob_sw_addr,
    output logic [W_BYTE_NUM-1:0]               rob_sw_strb,
    output logic                                rob_commit_mem_write,

    // FRAT interface
    output logic [ROB_INDEX_WIDTH-1:0]          rob_top_ptr,
    output logic                                rob_commit,

    // RRAT interface
    output logic [ARCH_REG_WIDTH-1:0]           rob_commit_rd_arch_addr,
    output logic                                rob_reg_write,
    output logic [PHY_REG_IDX_WIDTH-1:0]        rob_commit_curr_phy_addr,

    // FRL interface
    output logic [PHY_REG_IDX_WIDTH-1:0]        rob_commit_pre_phy_addr,

    // DISPATCH csr_stall release
    output logic                                rob_serializing_committed,
    output logic                                rob_fence_pending,
    output logic [ROB_INDEX_WIDTH-1:0]          rob_fence_tag,

    // CSR module interface (active during commit of CSR/trap/mret entries)
    output logic                                csr_commit_valid,
    output csr_addr_t                           csr_commit_addr,
    output csr_cmd_e                            csr_commit_cmd,
    output logic                                csr_commit_rs1_is_x0,
    output logic [4:0]                          csr_commit_zimm,
    output logic                                ecall_commit,
    output logic                                ebreak_commit,
    output logic                                mret_commit,
    output logic [PC_WIDTH-1:0]                 trap_commit_pc,

    // CSR module results (from CSR combinational read)
    input  logic [REG_FILE_DATA_WIDTH-1:0]      csr_rdata,
    input  logic                                csr_redirect_valid,
    input  logic [REG_FILE_DATA_WIDTH-1:0]      csr_redirect_pc,

    // PRF/RBA write port for CSR result (old CSR value -> rd)
    output logic [PHY_REG_IDX_WIDTH-1:0]        csr_wr_phy_addr,
    output logic [REG_FILE_DATA_WIDTH-1:0]      csr_wr_data,
    output logic                                csr_wr_en,

    // Trap flush: redirect front-end after ECALL/EBREAK/MRET commit
    // TODO: flush other parts, not only dispatch
    output logic                                trap_commit_flush,
    output logic [PC_WIDTH-1:0]                 trap_redirect_pc,

    // FENCE.I redirects fetch after all prior stores are globally complete.
    output logic                                fence_i_commit_flush,
    output logic [PC_WIDTH-1:0]                 fence_i_redirect_pc,

    // Cache-coherence handshake for FENCE.I (used when FENCE_I_COHERENCE=1).
    //   fence_i_coh_start : a FENCE.I is at the head, completed, and the store
    //                       buffer is drained — safe to begin I$/D$ sync.
    //   fence_i_coh_done  : the coherence controller has finished the sync;
    //                       FENCE.I may now commit and redirect fetch.
    output logic                                fence_i_coh_start,
    input  logic                                fence_i_coh_done
);

    typedef struct packed {
        logic [PHY_REG_IDX_WIDTH-1:0]       curr_phy;
        logic [PHY_REG_IDX_WIDTH-1:0]       prev_phy;
        logic [ARCH_REG_WIDTH-1:0]          rd_addr;
        logic                               rw;
        rob_opclass_t                       opclass;
        logic                               compl;
        logic [DMEM_ADDR_WIDTH-1:0]         sw_addr;
        logic [W_BYTE_NUM-1:0]              sw_strb;
        logic [PC_WIDTH-1:0]                pc;
        trap_cause_t                        trap_cause;
        csr_addr_t                          csr_addr;
        csr_cmd_e                           csr_cmd;
        logic [ARCH_REG_WIDTH-1:0]          rs1_arch;
    } rob_entry_t;

    rob_entry_t ROB_array [ROB_DEPTH];
    // the bottom_ptr and top_ptr are the pointers to the ROB_array
    // 5 bits for bottom_ptr and top_ptr, extra bit for overflow protection
    logic [ROB_INDEX_WIDTH:0] write_ptr, read_ptr, flush_ptr;
    logic [ROB_INDEX_WIDTH:0] rob_count;
    logic empty, full;

    rob_entry_t head;
    assign head = ROB_array[read_ptr[ROB_INDEX_WIDTH-1:0]];
    assign rob_count = write_ptr - read_ptr;

    logic enable;
    logic head_has_trap;
    assign head_has_trap = (head.opclass == ROB_TRAP);

    logic head_is_mret;
    assign head_is_mret = (head.opclass == ROB_MRET);

    logic head_is_serializing;
    assign head_is_serializing = (head.opclass == ROB_CSR) ||
                                 (head.opclass == ROB_TRAP) ||
                                 (head.opclass == ROB_MRET) ||
                                 (head.opclass == ROB_FENCE_I);

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
                ROB_array[write_ptr[ROB_INDEX_WIDTH-1:0]] <= '{
                    curr_phy:   (dis_rob_opclass == ROB_STORE) ?
                                dis_sw_rs2_phy_addr : dis_new_phy_addr,
                    prev_phy:   dis_pre_phy_addr,
                    rd_addr:    dis_rob_rd_arch_addr,
                    rw:         dis_reg_write,
                    opclass:    dis_rob_opclass,
                    compl:      (dis_rob_opclass == ROB_CSR) ||
                                (dis_rob_opclass == ROB_FENCE) ||
                                (dis_rob_opclass == ROB_FENCE_I) ||
                                (dis_rob_opclass == ROB_TRAP) ||
                                (dis_rob_opclass == ROB_MRET),
                    sw_addr:    '0,
                    sw_strb:    '0,
                    pc:         dis_pc,
                    trap_cause: dis_trap_cause,
                    csr_addr:   dis_csr_addr,
                    csr_cmd:    dis_csr_cmd,
                    rs1_arch:   dis_csr_rs1_arch_addr
                };
                write_ptr <= write_ptr + 1;
            end

            if (enable) begin
                read_ptr <= read_ptr + 1;
            end

            if (cdb_valid) begin
                if (ROB_array[cdb_rob_tag].opclass == ROB_STORE) begin
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
    assign rob_commit_mem_write = (head.opclass == ROB_STORE) && enable;
    assign st_src_phy_addr = (head.opclass == ROB_CSR) ?
                            rrat_csr_rs1_phy : head.curr_phy;

    // CFC interface
    assign rob_top_ptr = read_ptr[ROB_INDEX_WIDTH-1:0];
    assign rob_commit = enable;

    // RRAT interface
    assign rob_commit_rd_arch_addr = head.rd_addr;
    assign rob_reg_write = head.rw && enable;
    assign rob_commit_curr_phy_addr = head.curr_phy;

    // FRL interface
    assign rob_commit_pre_phy_addr = head.prev_phy;

    // DISPATCH csr_stall release
    assign rob_serializing_committed = enable && head_is_serializing;

    // CSR commit-time execution signals (active combinationally at head)
    assign csr_commit_valid   = enable && (head.opclass == ROB_CSR);
    assign csr_commit_addr    = head.csr_addr;
    assign csr_commit_cmd     = head.csr_cmd;
    assign csr_commit_rs1_is_x0 = (head.rs1_arch == ARCH_REG_WIDTH'(0));
    assign csr_commit_zimm    = 5'(head.rs1_arch);

    assign ecall_commit  = enable && (head.trap_cause == TRAP_CAUSE_ECALL_M);
    assign ebreak_commit = enable && (head.trap_cause == TRAP_CAUSE_EBREAK);

    assign mret_commit   = enable && head_is_mret;
    assign trap_commit_pc = head.pc;

    // CSR write-back to PRF for CSR instructions
    assign csr_wr_phy_addr = head.curr_phy;
    assign csr_wr_data     = csr_rdata;
    assign csr_wr_en       = enable && (head.opclass == ROB_CSR) && head.rw;

    // Trap/MRET flush and redirect
    assign trap_commit_flush = enable && (head_has_trap || head_is_mret);
    assign trap_redirect_pc  = csr_redirect_pc[PC_WIDTH-1:0];
    assign fence_i_commit_flush = enable && (head.opclass == ROB_FENCE_I);
    assign fence_i_redirect_pc  = head.pc + PC_WIDTH'(4);

    // Ready to synchronize the caches: a completed FENCE.I is at the head and
    // every older store has drained out of the store buffer into the D$.
    assign fence_i_coh_start = FENCE_I_COHERENCE && head.compl && !empty &&
                               (head.opclass == ROB_FENCE_I) && sb_drained;

    // The oldest in-flight fence is the load-issue ordering boundary.
    always_comb begin
        rob_fence_pending = 1'b0;
        rob_fence_tag = '0;
        for (int i = ROB_DEPTH - 1; i >= 0; i--) begin
            if ((ROB_INDEX_WIDTH + 1)'(i) < rob_count) begin
                if ((ROB_array[read_ptr[ROB_INDEX_WIDTH-1:0] +
                               ROB_INDEX_WIDTH'(i)].opclass == ROB_FENCE) ||
                    (ROB_array[read_ptr[ROB_INDEX_WIDTH-1:0] +
                               ROB_INDEX_WIDTH'(i)].opclass == ROB_FENCE_I)) begin
                    rob_fence_pending = 1'b1;
                    rob_fence_tag = read_ptr[ROB_INDEX_WIDTH-1:0] +
                                    ROB_INDEX_WIDTH'(i);
                end
            end
        end
    end

    always_comb begin
        enable = 1'b0;

        flush_ptr = '0;

        // commit from the top rule:
        // 1. the ROB entry is completed
        // 2. the ROB is not empty (avoid flushing the ROB)
        // 3. A store requires SB space.
        // 4. FENCE/FENCE.I require every older committed store response.
        // 5. With coherence enabled, FENCE.I also waits for the I$/D$ sync.
        if (head.compl && !empty &&
            ((head.opclass != ROB_STORE) || !sb_full) &&
            (((head.opclass != ROB_FENCE) &&
              (head.opclass != ROB_FENCE_I)) || sb_drained) &&
            ((head.opclass != ROB_FENCE_I) || !FENCE_I_COHERENCE ||
              fence_i_coh_done)) begin
            enable = 1'b1;
        end

        flush_ptr = ((write_ptr[ROB_INDEX_WIDTH-1:0] > cdb_rob_tag) ?
        {write_ptr[ROB_INDEX_WIDTH], cdb_rob_tag} : {~write_ptr[ROB_INDEX_WIDTH], cdb_rob_tag});
    end

    // synthesis translate_off
    // Simulation-only CDB capture. sim_cdb_rd_data is driven hierarchically from CPU
    logic [REG_FILE_DATA_WIDTH-1:0] sim_cdb_rd_data;
    logic [REG_FILE_DATA_WIDTH-1:0] sim_cdb_data_by_rob [ROB_DEPTH];
    logic [REG_FILE_DATA_WIDTH-1:0] sim_head_cdb_data;

    assign sim_head_cdb_data =
        sim_cdb_data_by_rob[read_ptr[ROB_INDEX_WIDTH-1:0]];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (int i = 0; i < ROB_DEPTH; i++) begin
                sim_cdb_data_by_rob[i] <= '0;
            end
        end else if (cdb_valid) begin
            sim_cdb_data_by_rob[cdb_rob_tag] <= sim_cdb_rd_data;
        end
    end
    // synthesis translate_on

endmodule
