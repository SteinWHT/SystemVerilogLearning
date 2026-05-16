module SAB #(
    parameter int unsigned SAB_DEPTH = 8,
    localparam int unsigned SAB_INDEX_WIDTH = $clog2(SAB_DEPTH),
    parameter int unsigned SB_DEPTH = 4,
    localparam int unsigned SB_INDEX_WIDTH = $clog2(SB_DEPTH),
    parameter int unsigned DMEM_WIDTH = 64,
    parameter int unsigned DMEM_DEPTH = 32,
    parameter int unsigned ROB_DEPTH = 16,
    localparam int unsigned ROB_INDEX_WIDTH = $clog2(ROB_DEPTH)
) (
    input logic clk,
    input logic rst_n,

    // SB interface
    input logic [SB_INDEX_WIDTH-1:0] sb_flush_sw_tag,
    input logic sb_flush_sw,
    input logic [SB_INDEX_WIDTH-1:0] sb_entry_sw_tag,

    // ROB interface
    input logic [ROB_INDEX_WIDTH-1:0] rob_tag,
    input logic [ROB_INDEX_WIDTH-1:0] rob_bottom_ptr,
    input logic rob_commit_mem_write,

    // LSQ interface
    input logic lsq_empty,
    
    output logic valid_out
);
    typedef struct packed {
        logic valid;
        logic [DMEM_DEPTH-1:0] addr;
        logic [ROB_INDEX_WIDTH-1:0] rob_tag;
        logic [SB_INDEX_WIDTH-1:0] sb_tag;
        logic tag_sel;
    } sab_entry_t;

    sab_entry_t SAB_array [0:SAB_DEPTH-1];
    logic [SAB_INDEX_WIDTH:0] write_ptr, read_ptr;

    assign valid_out = 1'b0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr <= '0;
            read_ptr  <= '0;
            for (int i = 0; i < SAB_DEPTH; i++) begin
                SAB_array[i] <= '0;
            end
        end
    end
endmodule