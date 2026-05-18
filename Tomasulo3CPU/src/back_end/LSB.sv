module LSB
import riscv_types_pkg::*;
#(
    parameter int unsigned LSB_DEPTH = 4,
    parameter int unsigned LSB_INDEX_WIDTH = $clog2(LSB_DEPTH),
    parameter int unsigned DMEM_DEPTH = 32,
    parameter int unsigned DMEM_WIDTH = 64,
    parameter int unsigned ROB_DEPTH = 16,
    parameter int unsigned ROB_INDEX_WIDTH = $clog2(ROB_DEPTH),
    parameter int unsigned ARCH_REG_WIDTH = 5,
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned REG_FILE_DATA_WIDTH = 64,
    parameter int unsigned OPCODE_WIDTH = 6
) (
    input logic clk,
    input logic rst_n,

    // D-Cache Interface
    input  logic                               dcache_read_done,
    input  logic [DMEM_WIDTH-1:0]              dcache_data,
    output logic                               dcache_ready,
    output logic [DMEM_DEPTH-1:0]              dcache_addr,

    // LSQ Interface
    input  logic [OPCODE_WIDTH-1:0]            iss_lsb_opcode,
    input  logic [ROB_INDEX_WIDTH-1:0]         iss_lsb_rob_tag,
    input  logic [DMEM_DEPTH-1:0]              iss_lsb_addr,
    input  logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_lsb_phy_addr,
    input  logic                               iss_lsb_rdy,
    output logic                               iss_lsb_ready,

    // Issue Unit Interface
    input  logic                               issue_ld_buf,
    output logic                               ready_ld_buf,

    // CDB Interface
    input  logic                               cdb_flush,
    input  logic [ROB_INDEX_WIDTH-1:0]         cdb_rob_depth,
    output logic [ROB_INDEX_WIDTH-1:0]         lsb_rob_tag,
    output logic [PHY_REGISTER_FILE_WIDTH-1:0] lsb_rd_phy_addr,
    output logic [REG_FILE_DATA_WIDTH-1:0]     lsb_data,
    output logic                               lsb_rw,
    output logic [DMEM_DEPTH-1:0]              lsb_sw_addr,
    output logic                               lsb_ready,

    // ROB Interface
    input  logic [ROB_INDEX_WIDTH-1:0]         rob_top_ptr
);

    typedef struct packed {
        logic [ROB_INDEX_WIDTH-1:0]         rob_tag;
        logic                               rw;
        logic [DMEM_DEPTH-1:0]              addr;
        logic [PHY_REGISTER_FILE_WIDTH-1:0] phy_addr;
        logic [REG_FILE_DATA_WIDTH-1:0]     data;
    } lsb_entry_t;

    lsb_entry_t lsb_array [LSB_DEPTH];
    logic [LSB_INDEX_WIDTH:0] write_ptr, read_ptr;

    lsb_entry_t lw_slot;
    logic       lw_slot_valid;
    logic       lw_slot_data_ready;

    //  Buffer status
    logic [LSB_INDEX_WIDTH:0] entry_count;
    logic lsb_full, lsb_empty;

    assign entry_count = write_ptr - read_ptr;
    assign lsb_full  = (write_ptr[LSB_INDEX_WIDTH]     != read_ptr[LSB_INDEX_WIDTH]) &&
                       (write_ptr[LSB_INDEX_WIDTH-1:0] == read_ptr[LSB_INDEX_WIDTH-1:0]);
    assign lsb_empty = (write_ptr == read_ptr);

    // Ready to accept a new instruction when the buffer has space,
    // the lw_slot is free (so a potential load can be serviced), and
    // no flush is in progress.
    assign iss_lsb_ready = !lsb_full && !lw_slot_valid && !cdb_flush;
    assign ready_ld_buf  = !lsb_empty && !cdb_flush;

    // D-Cache request: active while lw_slot awaits data
    assign dcache_ready = lw_slot_valid && !lw_slot_data_ready;
    assign dcache_addr  = lw_slot.addr;

    // ----------------------------------------------------------------
    //  Flush compaction (combinational pre-computation)
    //  Keeps entries whose ROB depth <= cdb_rob_depth (older or same
    //  age as the mispredicting branch) and removes younger ones.
    //  Entries are compacted towards the read_ptr end; write_ptr is
    //  adjusted to read_ptr + keep_count.
    // ----------------------------------------------------------------
    logic [LSB_INDEX_WIDTH:0] flush_keep_count;
    lsb_entry_t               flush_compact [LSB_DEPTH];
    logic                     flush_lw_slot;

    always_comb begin
        flush_keep_count = '0;
        for (int i = 0; i < LSB_DEPTH; i++)
            flush_compact[i] = lsb_array[i];

        for (int i = 0; i < LSB_DEPTH; i++) begin
            if (i[LSB_INDEX_WIDTH:0] < entry_count) begin
                if ((lsb_array[read_ptr[LSB_INDEX_WIDTH-1:0] + i[LSB_INDEX_WIDTH-1:0]].rob_tag
                     - rob_top_ptr) <= cdb_rob_depth) begin
                    flush_compact[read_ptr[LSB_INDEX_WIDTH-1:0]
                                  + flush_keep_count[LSB_INDEX_WIDTH-1:0]]
                        = lsb_array[read_ptr[LSB_INDEX_WIDTH-1:0] + i[LSB_INDEX_WIDTH-1:0]];
                    flush_keep_count = flush_keep_count + 1;
                end
            end
        end

        flush_lw_slot = lw_slot_valid &&
                        ((lw_slot.rob_tag - rob_top_ptr) > cdb_rob_depth);
    end

    // flush > {dcache_resp, deferred_xfer,new_instr, issue_to_cdb}
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr          <= '0;
            read_ptr           <= '0;
            lw_slot_valid      <= 1'b0;
            lw_slot_data_ready <= 1'b0;
            lw_slot            <= '0;
            lsb_ready          <= 1'b0;
            lsb_rob_tag        <= '0;
            lsb_rd_phy_addr    <= '0;
            lsb_data           <= '0;
            lsb_rw             <= '0;
            lsb_sw_addr        <= '0;
            for (int i = 0; i < LSB_DEPTH; i++)
                lsb_array[i] <= '0;

        end else if (cdb_flush) begin
            for (int i = 0; i < LSB_DEPTH; i++)
                lsb_array[i] <= flush_compact[i];
            write_ptr <= read_ptr + flush_keep_count;

            if (flush_lw_slot) begin
                lw_slot_valid      <= 1'b0;
                lw_slot_data_ready <= 1'b0;
            end
            lsb_ready <= 1'b0;

        end else begin
            // D-Cache read response
            if (dcache_read_done && lw_slot_valid && !lw_slot_data_ready) begin
                if (!lsb_full) begin
                    // Fast path: move completed load straight into the buffer
                    lsb_array[write_ptr[LSB_INDEX_WIDTH-1:0]] <= '{
                        rob_tag:  lw_slot.rob_tag,
                        rw:       lw_slot.rw,
                        addr:     lw_slot.addr,
                        phy_addr: lw_slot.phy_addr,
                        data:     dcache_data
                    };
                    write_ptr     <= write_ptr + 1;
                    lw_slot_valid <= 1'b0;
                end else begin
                    // Buffer full: park data in lw_slot until space opens
                    lw_slot.data       <= dcache_data;
                    lw_slot_data_ready <= 1'b1;
                end
            end

            // Deferred lw_slot -> buffer transfer
            if (lw_slot_valid && lw_slot_data_ready && !lsb_full) begin
                lsb_array[write_ptr[LSB_INDEX_WIDTH-1:0]] <= lw_slot;
                write_ptr          <= write_ptr + 1;
                lw_slot_valid      <= 1'b0;
                lw_slot_data_ready <= 1'b0;
            end

            // Accept new instruction from LSQ
            if (iss_lsb_rdy && iss_lsb_ready) begin
                if (iss_lsb_opcode == INSTR_LW) begin
                    lw_slot <= '{
                        rob_tag:  iss_lsb_rob_tag,
                        rw:       1'b1,
                        addr:     iss_lsb_addr,
                        phy_addr: iss_lsb_phy_addr,
                        data:     '0
                    };
                    lw_slot_valid      <= 1'b1;
                    lw_slot_data_ready <= 1'b0;
                end else begin
                    lsb_array[write_ptr[LSB_INDEX_WIDTH-1:0]] <= '{
                        rob_tag:  iss_lsb_rob_tag,
                        rw:       1'b0,
                        addr:     iss_lsb_addr,
                        phy_addr: iss_lsb_phy_addr,
                        data:     '0
                    };
                    write_ptr <= write_ptr + 1;
                end
            end

            // Issue head entry to CDB
            if (issue_ld_buf && !lsb_empty) begin
                lsb_rob_tag     <= lsb_array[read_ptr[LSB_INDEX_WIDTH-1:0]].rob_tag;
                lsb_rd_phy_addr <= lsb_array[read_ptr[LSB_INDEX_WIDTH-1:0]].phy_addr;
                lsb_data        <= lsb_array[read_ptr[LSB_INDEX_WIDTH-1:0]].data;
                lsb_rw          <= lsb_array[read_ptr[LSB_INDEX_WIDTH-1:0]].rw;
                lsb_sw_addr     <= lsb_array[read_ptr[LSB_INDEX_WIDTH-1:0]].addr;
                read_ptr        <= read_ptr + 1;
                lsb_ready       <= 1'b1;
            end else begin
                lsb_ready       <= 1'b0;
            end
        end
    end

    // Assertions
    // synthesis translate_off
    always_ff @(posedge clk) begin
        if (rst_n) begin
            LSB_BUFFER_OVERFLOW: assert (entry_count <= LSB_DEPTH)
                else $error("LSB: buffer overflow, entry_count = %0d", entry_count);
        end
    end
    // synthesis translate_on

endmodule
