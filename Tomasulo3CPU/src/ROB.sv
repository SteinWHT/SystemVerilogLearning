// 32 entries
// ROB Entry Format for non-SW instruction:
// curr_phy         prev_phy        rd_addr         rw          mw          compl       sw_addr(unused)     total
// 6bits            6bits           5bits           1bit        1bit        1bit        21bits              41bits
// ROB Entry Format for SW instruction:
// curr_phy         sw_addr1        rw              mw          compl       sw_addr2    total
// 6bits            11bits          1bit            1bit        1bit        21bits      41bits
// curr_phy: the current physical register index with stored data
// prev_phy: the previous physical register index with stored data
// rd_addr: the architectural address of the destination register
// rw: 1: register write for load instruction, integer and JAL instructions
// mw: 1: memory write for store instruction
// compl: 1 for completed, 0 for not completed
// sw_addr1: the 11 bits of the store address part1
// sw_addr2: the 21 bits of the store address part2

// read ptr = top ptr -> commit from the top
// write ptr = bottom ptr -> dispatch from the bottom

module ROB #(
    parameter int unsigned ROB_DEPTH = 32,
    parameter int unsigned ROB_INDEX_WIDTH = $clog2(ROB_DEPTH),
    parameter int unsigned DMEM_WIDTH = 64,
    parameter int unsigned DMEM_DEPTH = 32,
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

    output logic [ROB_INDEX_WIDTH-1:0]          rob_bottom_ptr,
    output logic                                rob_full,
    output logic                                rob_two_or_more_vacant,

    // CDB interface
    input logic                                 cdb_valid,
    input logic [ROB_INDEX_WIDTH-1:0]           cdb_rob_tag,
    input logic [DMEM_DEPTH-1:0]                cdb_sw_addr,
    input logic [W_BYTE_NUM-1:0]                cdb_sw_strb,
    input logic                                 cdb_flush,

    // PRF interface
    input logic [DMEM_WIDTH-1:0]                cdb_sw_data,

    // SB interface
    input logic sb_full,
    output logic [DMEM_DEPTH-1:0]               rob_sw_addr,
    output logic [DMEM_WIDTH-1:0]               rob_sw_data,
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
    output logic [PHY_REGISTER_FILE_WIDTH-1:0]  rob_commit_pre_phy_addr
    // shared with other interfaces
    // output logic rob_commit,
    // output logic rob_reg_write,
);

    typedef struct packed {
        logic [PHY_REGISTER_FILE_WIDTH-1:0] curr_phy;
        logic [PHY_REGISTER_FILE_WIDTH-1:0] prev_phy;
        logic [ARCH_REG_WIDTH-1:0]          rd_addr;
        logic                               rw;
        logic                               mw;
        logic                               compl;
        logic [DMEM_DEPTH-1:0]              sw_addr;
        logic [DMEM_WIDTH-1:0]              sw_data;
        logic [W_BYTE_NUM-1:0]              sw_strb;
    } rob_entry_t;

    rob_entry_t ROB_array [ROB_DEPTH];
    // the bottom_ptr and top_ptr are the pointers to the ROB_array
    // 5 bits for bottom_ptr and top_ptr, extra bit for overflow protection
    logic [ROB_INDEX_WIDTH:0] write_ptr, read_ptr, flush_ptr;
    logic empty, full;

    rob_entry_t head;
    assign head = ROB_array[read_ptr[ROB_INDEX_WIDTH-1:0]];

    logic enable;
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
                        curr_phy: dis_sw_rt_phy_addr,
                        prev_phy: '0,
                        rd_addr:  '0,
                        rw:       1'b0,
                        mw:       1'b1,
                        compl:    1'b0,
                        sw_addr:  '0,
                        sw_data:  '0,
                        sw_strb:  '0
                    };
                end else begin
                    ROB_array[write_ptr[ROB_INDEX_WIDTH-1:0]] <= '{
                        curr_phy: dis_new_phy_addr,
                        prev_phy: dis_pre_phy_addr,
                        rd_addr:  dis_rob_rd_arch_addr,
                        rw:       dis_reg_write,
                        mw:       1'b0,
                        compl:    1'b0,
                        sw_addr:  '0,
                        sw_data:  '0,
                        sw_strb:  '0
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
                    ROB_array[cdb_rob_tag].sw_data <= cdb_sw_data;
                    ROB_array[cdb_rob_tag].sw_strb <= cdb_sw_strb;
                end
                ROB_array[cdb_rob_tag].compl <= 1'b1;
            end

            if (cdb_flush) begin
                // flush the ROB
                write_ptr <= flush_ptr + 1'b1;
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
    // assign rob_empty = empty;
    assign rob_two_or_more_vacant = ((write_ptr - read_ptr) <=
                                    (ROB_INDEX_WIDTH + 1)'(ROB_DEPTH - 2));

    // SB interface
    assign rob_sw_addr = head.sw_addr;
    assign rob_sw_data = head.sw_data;
    assign rob_sw_strb = head.sw_strb;
    assign rob_commit_mem_write = head.mw && enable;

    // CFC interface
    assign rob_top_ptr = read_ptr[ROB_INDEX_WIDTH-1:0];
    assign rob_commit = enable;

    // RRAT interface
    assign rob_commit_rd_arch_addr = head.rd_addr;
    assign rob_reg_write = head.rw && enable;
    assign rob_commit_curr_phy_addr = head.curr_phy;

    // FRL interface
    assign rob_commit_pre_phy_addr = head.prev_phy;

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


endmodule
