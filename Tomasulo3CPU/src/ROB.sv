// 32 entries
// ROB Entry Format for non-SW instruction:
// curr_phy         prev_phy        rd_addr         rw          mw          compl       sw_addr(unused)     total
// 6bits            6bits           5bits           1bit        1bit        1bit        21bits              41bits
// ROB Entry Format for SW instruction:
// curr_phy         sw_addr1        rw              mw          compl       sw_addr2    total
// 6bits            11bits          1bit            1bit        1bit        21bits      41bits
// curr_phy: the current physical register index with stored data
// prev_phy: the previous physical register index with stored data
// rd_addr: the architectural address of the register to be read
// rw: 1: register write for load instruction, integer and JAL instructions
// mw: 1: memory write for store instruction
// compl: 1 for completed, 0 for not completed
// sw_addr1: the 11 bits of the store address part1
// sw_addr2: the 21 bits of the store address part2

module ROB #(
    parameter int unsigned ROB_ENTRY_WIDTH = 41,
    parameter int unsigned ROB_DEPTH = 32,
    parameter int unsigned ROB_INDEX_WIDTH = $clog2(ROB_DEPTH),
    parameter int unsigned DMEM_WIDTH = 32,
    parameter int unsigned ARCH_REG_COUNT = 32,
    parameter int unsigned ARCH_REG_WIDTH = $clog2(ARCH_REG_COUNT),
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7
) (
    input logic clk,
    input logic rst_n,

    // DISPATCH interface
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_sw_rt_phy_addr,
    input logic dis_inst_sw,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_pre_phy_addr,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_new_phy_addr,
    input logic dis_inst_valid,
    input logic [ARCH_REG_WIDTH-1:0] dis_rob_rd_arch_addr,
    //input logic [PHY_REGISTER_FILE_WIDTH-1:0] dis_sw_rt_phy_addr,
    input logic dis_reg_write,

    output logic [ROB_INDEX_WIDTH-1:0] rob_bottom_ptr,
    output logic rob_full,
    output logic rob_two_or_more_vacant,

    // CDB interface
    input logic cdb_valid,
    input logic [ROB_INDEX_WIDTH-1:0] cdb_rob_tag,
    input logic [DMEM_WIDTH-1:0] cdb_sw_addr,
    // TODO: check if this is correct
    input logic cdb_branch_mispredict,

    // SB interface
    input logic sb_full,

    output logic [DMEM_WIDTH-1:0] rob_sw_addr, 
    output logic rob_commit_mem_write,

    // CFC interface
    output logic [ROB_INDEX_WIDTH-1:0] rob_top_ptr,
    output logic rob_commit,

    // RRAT interface
    output logic [ARCH_REG_WIDTH-1:0] rob_commit_rd_arch_addr,
    output logic rob_reg_write,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0] rob_commit_curr_phy_addr,

    // FRL interface
    output logic [PHY_REGISTER_FILE_WIDTH-1:0] rob_commit_pre_phy_addr
    // shared with other interfaces
    // output logic rob_commit,
    // output logic rob_reg_write,
);

    logic [ROB_ENTRY_WIDTH-1:0] ROB_array [0:ROB_DEPTH-1];
    // the bottom_ptr and top_ptr are the pointers to the ROB_array
    // 5 bits for bottom_ptr and top_ptr, extra bit for overflow protection
    logic [ROB_INDEX_WIDTH:0] write_ptr, read_ptr, flush_ptr;
    logic empty, full;


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
                    ROB_array[write_ptr] <= {dis_new_phy_addr, dis_pre_phy_addr, dis_sw_rt_phy_addr, 
                                            dis_reg_write, 1'b0, 1'b0, 21'b0};
                end else begin
                    ROB_array[write_ptr] <= {dis_sw_rt_phy_addr, 11'b0, 1'b0, 1'b1, 1'b0, 21'b0};
                end
                write_ptr <= write_ptr + 1;
            end
            
            if (enable) begin
                read_ptr <= read_ptr + 1;
            end

            if (cdb_valid) begin
                // if mw is 1, update the SW address
                if (ROB_array[cdb_rob_tag][22]) begin
                    ROB_array[cdb_rob_tag][34:24] <= cdb_sw_addr[31:21];
                    ROB_array[cdb_rob_tag][20:0] <= cdb_sw_addr[20:0];
                end
                // complete the instruction
                ROB_array[cdb_rob_tag][21] <= 1'b1;
            end

            if (cdb_branch_mispredict) begin
                // flush the ROB
                write_ptr <= flush_ptr;
            end
        end
    end

    
    assign full = ((write_ptr[ROB_INDEX_WIDTH] != read_ptr[ROB_INDEX_WIDTH]) && (write_ptr[ROB_INDEX_WIDTH-1:0] == read_ptr[ROB_INDEX_WIDTH-1:0]));
    assign empty = ((write_ptr[ROB_INDEX_WIDTH] == read_ptr[ROB_INDEX_WIDTH]) && (write_ptr[ROB_INDEX_WIDTH-1:0] == read_ptr[ROB_INDEX_WIDTH-1:0]));
    
    // CDB interface
    assign rob_bottom_ptr = write_ptr[ROB_INDEX_WIDTH-1:0];
    assign rob_full = full;
    assign rob_empty = empty;
    // TODO: check if this is correct
    assign rob_two_or_more_vacant = ((write_ptr - read_ptr) <= ROB_DEPTH - 2);

    // SB interface
    assign rob_sw_addr = {ROB_array[read_ptr][34:24], ROB_array[read_ptr][20:0]};
    assign rob_commit_mem_write = ROB_array[read_ptr][22];

    // CFC interface
    assign rob_top_ptr = read_ptr[ROB_INDEX_WIDTH-1:0];
    assign rob_commit = enable;
    
    // RRAT interface
    assign rob_commit_rd_arch_addr = ROB_array[read_ptr][38:27];
    assign rob_reg_write = ROB_array[read_ptr][26];
    assign rob_commit_curr_phy_addr = ROB_array[read_ptr][25:19];

    // FRL interface
    assign rob_commit_pre_phy_addr = ROB_array[read_ptr][34:29];

    always_comb begin
        enable = 1'b0;

        flush_ptr = '0;

        // commit from the top rule:
        // 1. the ROB entry is completed
        // 2. the ROB is not empty (avoid flushing the ROB)
        // 3. MW is 0 or (MW is 1 and SB is not full)
        if (ROB_array[read_ptr][21] && !empty && (!ROB_array[read_ptr][22] || (!sb_full && ROB_array[read_ptr][22]))) begin
            enable = 1'b1;
        end

        if (cdb_branch_mispredict) begin
            flush_ptr = (write_ptr[ROB_INDEX_WIDTH-1:0] > cdb_rob_tag)? {write_ptr[ROB_INDEX_WIDTH], cdb_rob_tag} : {~write_ptr[ROB_INDEX_WIDTH], cdb_rob_tag};
        end
    end


endmodule