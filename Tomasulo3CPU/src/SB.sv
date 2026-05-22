module SB #(
    parameter int unsigned SB_DEPTH = 4,
    parameter int unsigned SB_INDEX_WIDTH = $clog2(SB_DEPTH),
    parameter int unsigned DMEM_WIDTH = 64,
    parameter int unsigned DMEM_DEPTH = 32,
    parameter int unsigned W_BYTE_NUM = DMEM_WIDTH / 8
) (
    input logic clk,
    input logic rst_n,

    // ROB interface
    input logic [DMEM_DEPTH-1:0]        rob_sw_addr,
    input logic [DMEM_WIDTH-1:0]        rob_sw_data,
    input logic [W_BYTE_NUM-1:0]        rob_sw_strb,
    input logic                         rob_commit_mem_write,

    // D-CACHE interface
    input logic                         dcache_valid,
    input logic                         dcache_resp_valid,

    output logic [DMEM_DEPTH-1:0]       dcache_sw_addr,
    output logic [W_BYTE_NUM-1:0]       dcache_wstrb,
    output logic [DMEM_WIDTH-1:0]       dcache_sw_data,
    output logic                        dcache_ready,
    output logic                        dcache_resp_ready,

    // SAB interface
    output logic [SB_INDEX_WIDTH-1:0]   sb_flush_sw_tag,
    output logic                        sb_flush_sw,
    output logic [SB_INDEX_WIDTH-1:0]   sb_entry_sw_tag,
    // TODO: check if this is needed
    output logic [DMEM_DEPTH-1:0]       sb_entry_sw_addr,

    output logic                        full,
    output logic                        empty
);
    typedef struct packed {
        logic [DMEM_DEPTH-1:0]              sw_addr;
        logic [DMEM_WIDTH-1:0]              sw_data;
        logic [W_BYTE_NUM-1:0]              sw_strb;
    } sb_entry_t;
    
    sb_entry_t sb_array [SB_DEPTH];
    logic [SB_INDEX_WIDTH:0] write_ptr, read_ptr_lead, read_ptr_trail;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            write_ptr <= '0;
            read_ptr_lead <= '0;
            read_ptr_trail <= '0;
            for (int i = 0; i < SB_DEPTH; i++) begin
                sb_array[i] <= '0;
            end
        end else begin
            if (rob_commit_mem_write && !full) begin
                sb_array[write_ptr[SB_INDEX_WIDTH-1:0]] <= 
                    '{sw_addr: rob_sw_addr,
                      sw_data: rob_sw_data,
                      sw_strb: rob_sw_strb};
                write_ptr <= write_ptr + 1;
                sb_entry_sw_tag <= write_ptr[SB_INDEX_WIDTH-1:0];
                sb_entry_sw_addr <= rob_sw_addr;
            end

            if (dcache_valid && !empty) begin
                read_ptr_lead <= read_ptr_lead + 1;
            end

            if (dcache_resp_valid) begin
                read_ptr_trail <= read_ptr_trail + 1;
                sb_flush_sw_tag <= read_ptr_trail[SB_INDEX_WIDTH-1:0];
                sb_flush_sw <= 1'b1;
            end else begin
                sb_flush_sw <= 1'b0;
            end
        end
    end

    assign empty = (write_ptr[SB_INDEX_WIDTH] == read_ptr_lead[SB_INDEX_WIDTH]) && (write_ptr[SB_INDEX_WIDTH-1:0] == read_ptr_lead[SB_INDEX_WIDTH-1:0]);
    assign full = ((write_ptr[SB_INDEX_WIDTH] != read_ptr_trail[SB_INDEX_WIDTH]) && (write_ptr[SB_INDEX_WIDTH-1:0] == read_ptr_trail[SB_INDEX_WIDTH-1:0]));

    assign dcache_sw_addr = sb_array[read_ptr_lead[SB_INDEX_WIDTH-1:0]].sw_addr;
    assign dcache_sw_data = sb_array[read_ptr_lead[SB_INDEX_WIDTH-1:0]].sw_data;
    assign dcache_sw_strb = sb_array[read_ptr_lead[SB_INDEX_WIDTH-1:0]].sw_strb;
    assign dcache_ready = !empty;
    assign dcache_resp_ready = (read_ptr_lead != read_ptr_trail);
endmodule
