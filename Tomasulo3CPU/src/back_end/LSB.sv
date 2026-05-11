module LSB #(
    parameter int unsigned LSB_DEPTH = 4,
    localparam int unsigned LSB_INDEX_WIDTH = $clog2(LSB_DEPTH),
    parameter int unsigned DMEM_DEPTH = 32,
    parameter int unsigned ROB_DEPTH = 16,
    localparam int unsigned ROB_INDEX_WIDTH = $clog2(ROB_DEPTH),
    parameter int unsigned ARCH_REG_WIDTH = 5,
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned REG_FILE_DATA_WIDTH = 64,
    parameter int unsigned OPCODE_WIDTH = 1,
    parameter int unsigned LD_ST_OPCODE_WIDTH = 1,

    localparam int unsigned OPCODE_LOAD = 1'b0,
    localparam int unsigned OPCODE_STORE = 1'b1
) (
    input logic clk,
    input logic rst_n,

    // D-Cache Interface
    input logic dcache_read_done,
    input logic [DMEM_DEPTH-1:0] dcache_data,

    output logic dcache_ready,
    output logic [DMEM_DEPTH-1:0] dcache_addr,

    // ISSUEQ Interface
    input logic [LD_ST_OPCODE_WIDTH-1:0] iss_lsb_opcode,
    input logic [ROB_INDEX_WIDTH-1:0] iss_lsb_rob_tag,
    input logic [DMEM_DEPTH-1:0] iss_lsb_addr,
    input logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_lsb_phy_addr,
    input logic iss_lsb_rdy,
    output logic iss_lsb_ready,

    // ISSUE UNIT Interface
    input logic issue_ld_buf,
    output logic ready_ld_buf,
    
    // CDB Interface
    input logic cdb_flush,
    input logic [ROB_INDEX_WIDTH-1:0] cdb_rob_depth,

    output logic [ROB_INDEX_WIDTH-1:0] lsb_rob_tag,
    output logic [DMEM_DEPTH-1:0] lsb_rd_phy_addr,
    output logic [REG_FILE_DATA_WIDTH-1:0] lsb_data,
    output logic lsb_rw,
    output logic [DMEM_DEPTH-1:0] lsb_sw_addr,
    output logic lsb_ready,

    // ROB Interface
    input logic [ROB_INDEX_WIDTH-1:0] rob_top_ptr
);
    typedef struct packed {
        logic [ROB_INDEX_WIDTH-1:0] rob_tag;
        logic rw;
        logic [DMEM_DEPTH-1:0] addr;
        logic [PHY_REGISTER_FILE_WIDTH-1:0] phy_addr;
        logic [REG_FILE_DATA_WIDTH-1:0] data;
    } lsb_entry;

    lsb_entry lsb_array [0:LSB_DEPTH-1];
    logic [LSB_DEPTH-1:0] lsb_valid;
    logic lsb_full;
    logic lsb_empty;
    logic [LSB_INDEX_WIDTH:0] write_ptr, read_ptr;

    // one slot for lw instruction due to dcache read latency
    lsb_entry lw_slot_entry;
    logic lw_slot_ready;
    logic lw_slot_valid;

    logic [ROB_INDEX_WIDTH-1:0] lsb_entry_depth [0:LSB_DEPTH-1];
    logic [ROB_INDEX_WIDTH-1:0] lsb_entry_depth_lw;
    // Entry Depth
    always_comb begin
        for (int i = read_ptr[LSB_INDEX_WIDTH-1:0]; i < write_ptr[LSB_INDEX_WIDTH-1:0]; i++) begin
            lsb_entry_depth[i] = lsb_array[i].rob_tag[ROB_INDEX_WIDTH-1:0] - rob_top_ptr;
        end
        lsb_entry_depth_lw = lw_slot_entry.rob_tag[ROB_INDEX_WIDTH-1:0] - rob_top_ptr;
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr <= '0;
            read_ptr <= '0;
            for (int i = 0; i < LSB_DEPTH; i++) begin
                lsb_array[i] <= '0;
            end
        end else begin
            // Store the instruction if there is a free slot
            // TODO: Optimize the logic for lw slot
            // Does it introduce worse traffic?
            // Since it prefers the sw.
            if (iss_lsb_rdy && !lsb_full) begin
                if (iss_lsb_opcode == OPCODE_LOAD) begin
                    lw_slot_entry <= '{
                        rob_tag: iss_lsb_rob_tag,
                        rw: 1'b1,
                        addr: '0,
                        phy_addr: iss_lsb_phy_addr,
                        data: '0};
                    lw_slot_valid <= 1'b1;
                    lw_slot_ready <= 1'b0;
                    dcache_ready <= 1'b1;

                    if (lw_slot_valid && lw_slot_ready) begin
                        lsb_array[write_ptr] <= lw_slot_entry;
                        write_ptr <= write_ptr + 1;
                    end
                end
                else begin
                    lsb_array[write_ptr] <= '{
                        rob_tag: iss_lsb_rob_tag,
                        rw: 1'b0,
                        addr: iss_lsb_addr,
                        phy_addr: iss_lsb_phy_addr,
                        data: '0};
                    write_ptr <= write_ptr + 1;
                end
            end else if (lw_slot_valid && lw_slot_ready) begin
                lsb_array[write_ptr] <= lw_slot_entry;
                write_ptr <= write_ptr + 1;
                lw_slot_valid <= 1'b0;
                lw_slot_ready <= 1'b0;
                dcache_ready <= 1'b0;
            end else begin
                dcache_ready <= 1'b0;
            end 

            // TODO: Assertion check if dcache_read_done is asserted when lw_slot_valid is asserted
            if(dcache_read_done && lw_slot_valid&&!lw_slot_ready) begin
                lw_slot_ready <= 1'b1;
                lw_slot_entry.data <= dcache_data;
            end

            // Issue the instruction
            if (issue_ld_buf && !lsb_empty) begin
                lsb_rob_tag <= lsb_array[read_ptr].rob_tag;
                lsb_rd_phy_addr <= lsb_array[read_ptr].phy_addr;
                lsb_data <= lsb_array[read_ptr].data;
                lsb_rw <= lsb_array[read_ptr].rw;
                lsb_sw_addr <= lsb_array[read_ptr].addr;
                read_ptr <= read_ptr + 1;
                lsb_ready <= 1'b1;
            end

            // Flush the instruction
            if (cdb_flush) begin
                automatic int slot = 0;
                for (int i = read_ptr[LSB_INDEX_WIDTH-1:0]; i < write_ptr[LSB_INDEX_WIDTH-1:0]; i++) begin
                    if (lsb_entry_depth[i] > cdb_rob_depth) begin
                        slot ++;
                    end else begin
                        lsb_array[i - slot] <= lsb_array[i];
                    end
                end
                read_ptr <= read_ptr + slot;
                if (lw_slot_valid && (lsb_entry_depth_lw > cdb_rob_depth)) begin
                    lw_slot_valid <= 1'b0;
                    lw_slot_ready <= 1'b0;
                end
            end
        end
    end

    assign lsb_full = (write_ptr[LSB_INDEX_WIDTH] != read_ptr[LSB_INDEX_WIDTH]) && (write_ptr[LSB_INDEX_WIDTH-1:0] == read_ptr[LSB_INDEX_WIDTH-1:0]);
    assign iss_lsb_ready = !lsb_full && !cdb_flush;
    assign lsb_empty = (write_ptr[LSB_INDEX_WIDTH] == read_ptr[LSB_INDEX_WIDTH]) && (write_ptr[LSB_INDEX_WIDTH-1:0] == read_ptr[LSB_INDEX_WIDTH-1:0]);
    assign ready_ld_buf = !lsb_empty && !cdb_flush;
endmodule