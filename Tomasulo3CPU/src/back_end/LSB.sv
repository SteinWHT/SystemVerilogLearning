// LSB execute an extra stage to align other instructions to execute
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
    parameter int unsigned OPCODE_WIDTH = 6,
    parameter int unsigned W_BYTE_NUM = DMEM_WIDTH / 8
) (
    input logic clk,
    input logic rst_n,

    // D-Cache Interface
    input  logic                               dcache_resp_valid,
    input  logic [DMEM_WIDTH-1:0]              dcache_data,
    output logic                               dcache_resp_ready,

    // LSQ Interface
    input  logic [OPCODE_WIDTH-1:0]            iss_lsb_opcode,
    input  logic [ROB_INDEX_WIDTH-1:0]         iss_lsb_rob_tag,
    input  logic [DMEM_DEPTH-1:0]              iss_lsb_addr,
    input  logic [PHY_REGISTER_FILE_WIDTH-1:0] iss_lsb_phy_addr,
    input  logic                               iss_lsb_rdy,
    output logic                               lsb_en,

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
    output logic [W_BYTE_NUM-1:0]              lsb_sw_strb,
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
        logic [W_BYTE_NUM-1:0]              strb;
    } lsb_entry_t;

    lsb_entry_t lsb_array [LSB_DEPTH];
    logic [LSB_INDEX_WIDTH:0] write_ptr, read_ptr;

    lsb_entry_t lw_slot;
    logic [OPCODE_WIDTH-1:0] lw_slot_opcode;
    logic       lw_slot_valid;
    logic       lw_slot_data_ready;

    logic issue_ld_buf_reg;

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
    assign lsb_en = !lsb_full && !lw_slot_valid && !cdb_flush;
    assign ready_ld_buf  = !lsb_empty && !cdb_flush;

    // D-Cache request: active while lw_slot awaits data
    assign dcache_resp_ready = lw_slot_valid && !lw_slot_data_ready;

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


    logic [W_BYTE_NUM-1:0] store_strb;
    logic [$clog2(W_BYTE_NUM)-1:0] byte_off;
    assign byte_off = iss_lsb_addr[$clog2(W_BYTE_NUM)-1:0];

    always_comb begin
        unique case (iss_lsb_opcode)
            INSTR_SB: store_strb = {{(W_BYTE_NUM-1){1'b0}}, 1'b1}    << byte_off;
            INSTR_SH: store_strb = {{(W_BYTE_NUM-2){1'b0}}, 2'b11}   << byte_off;
            INSTR_SW: store_strb = {{(W_BYTE_NUM-4){1'b0}}, 4'b1111} << byte_off;
            INSTR_SD: store_strb = {W_BYTE_NUM{1'b1}}                << byte_off;
            default:  store_strb = {W_BYTE_NUM{1'b1}};
        endcase
    end

    logic [REG_FILE_DATA_WIDTH-1:0] load_data_aligned;
    logic [2:0] r_byte_off;
    assign r_byte_off = lw_slot.addr[2:0];

    always_comb begin
        load_data_aligned = dcache_data;
        unique case (lw_slot_opcode)
            INSTR_LB: begin
                load_data_aligned = {{56{dcache_data[r_byte_off*8 + 7]}}, dcache_data[r_byte_off*8 +: 8]};
            end
            INSTR_LBU: begin
                load_data_aligned = {56'b0, dcache_data[r_byte_off*8 +: 8]};
            end
            INSTR_LH: begin
                load_data_aligned = {{48{dcache_data[r_byte_off*8 + 15]}}, dcache_data[r_byte_off*8 +: 16]};
            end
            INSTR_LHU: begin
                load_data_aligned = {48'b0, dcache_data[r_byte_off*8 +: 16]};
            end
            INSTR_LW: begin
                load_data_aligned = {{32{dcache_data[r_byte_off*8 + 31]}}, dcache_data[r_byte_off*8 +: 32]};
            end
            INSTR_LWU: begin
                load_data_aligned = {32'b0, dcache_data[r_byte_off*8 +: 32]};
            end
            INSTR_LD: begin
                load_data_aligned = dcache_data;
            end
            default: begin
                load_data_aligned = dcache_data;
            end
        endcase
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
            lsb_sw_strb        <= '0;
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
            if (dcache_resp_valid && lw_slot_valid && !lw_slot_data_ready) begin
                if (!lsb_full) begin
                    // Fast path: move completed load straight into the buffer
                    lsb_array[write_ptr[LSB_INDEX_WIDTH-1:0]] <= '{
                        rob_tag:  lw_slot.rob_tag,
                        rw:       lw_slot.rw,
                        addr:     lw_slot.addr,
                        phy_addr: lw_slot.phy_addr,
                        data:     load_data_aligned,
                        strb:     lw_slot.strb
                    };
                    write_ptr     <= write_ptr + 1;
                    lw_slot_valid <= 1'b0;
                end else begin
                    // Buffer full: park data in lw_slot until space opens
                    lw_slot.data       <= load_data_aligned;
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
            if (iss_lsb_rdy && lsb_en) begin
                if (iss_lsb_opcode == INSTR_LW  || iss_lsb_opcode == INSTR_LD  ||
                    iss_lsb_opcode == INSTR_LB  || iss_lsb_opcode == INSTR_LH  ||
                    iss_lsb_opcode == INSTR_LBU || iss_lsb_opcode == INSTR_LHU ||
                    iss_lsb_opcode == INSTR_LWU) begin
                    lw_slot <= '{
                        rob_tag:  iss_lsb_rob_tag,
                        rw:       1'b1,
                        addr:     iss_lsb_addr,
                        phy_addr: iss_lsb_phy_addr,
                        data:     '0,
                        strb:     '0
                    };
                    lw_slot_opcode     <= iss_lsb_opcode;
                    lw_slot_valid      <= 1'b1;
                    lw_slot_data_ready <= 1'b0;
                end else begin
                    lsb_array[write_ptr[LSB_INDEX_WIDTH-1:0]] <= '{
                        rob_tag:  iss_lsb_rob_tag,
                        rw:       1'b0,
                        addr:     iss_lsb_addr,
                        phy_addr: iss_lsb_phy_addr,
                        data:     '0,
                        strb:     store_strb
                    };
                    write_ptr <= write_ptr + 1;
                end
            end
            if(issue_ld_buf && !lsb_empty) begin
                issue_ld_buf_reg <= 1'b1;
            end else begin
                issue_ld_buf_reg <= 1'b0;
            end

            // Issue head entry to CDB
            if (issue_ld_buf_reg && !lsb_empty) begin
                lsb_rob_tag     <= lsb_array[read_ptr[LSB_INDEX_WIDTH-1:0]].rob_tag;
                lsb_rd_phy_addr <= lsb_array[read_ptr[LSB_INDEX_WIDTH-1:0]].phy_addr;
                lsb_data        <= lsb_array[read_ptr[LSB_INDEX_WIDTH-1:0]].data;
                lsb_rw          <= lsb_array[read_ptr[LSB_INDEX_WIDTH-1:0]].rw;
                lsb_sw_addr     <= lsb_array[read_ptr[LSB_INDEX_WIDTH-1:0]].addr;
                lsb_sw_strb     <= lsb_array[read_ptr[LSB_INDEX_WIDTH-1:0]].strb;
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
            LSB_DCACHE_LATENCY: assert (!(!lw_slot_valid && dcache_resp_ready))
                else $error("LSB: DCACHE is expected to have at least one cycle latency");
        end
    end
    // synthesis translate_on

endmodule
