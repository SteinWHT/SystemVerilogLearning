// Behavioral backing memory: word-addressable (64-bit) SRAM, 1-cycle ack.
// Read-only for I-cache tests; write port kept for testbench preload.

module icache_backing_mem #(
    parameter int unsigned DEPTH     = icache_pkg::MEM_DEPTH,
    parameter int unsigned WORD_BITS = icache_pkg::MEM_WORD_BITS,
    parameter int unsigned IDX_BITS  = icache_pkg::MEM_IDX_BITS
) (
    input  logic                  clk,
    input  logic                  rst_n,

    input  logic                  req,
    input  logic                  we,
    input  logic [IDX_BITS-1:0]   idx,
    input  logic [WORD_BITS-1:0]  wdata,
    output logic [WORD_BITS-1:0]  rdata,
    output logic                  ack,

    input  logic                  init_en,
    input  logic [IDX_BITS-1:0]   init_idx,
    input  logic [WORD_BITS-1:0]  init_data
);
    logic [WORD_BITS-1:0] mem [DEPTH];
    logic                 pending_q;
    logic [WORD_BITS-1:0] rdata_q;

    assign ack   = pending_q;
    assign rdata = rdata_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pending_q <= 1'b0;
            rdata_q   <= '0;
            if (init_en)
                mem[init_idx] <= init_data;
        end else begin
            pending_q <= 1'b0;
            if (init_en) begin
                mem[init_idx] <= init_data;
            end else if (req && !pending_q) begin
                pending_q <= 1'b1;
                if (we)
                    mem[idx] <= wdata;
                else
                    rdata_q  <= mem[idx];
            end
        end
    end

endmodule
