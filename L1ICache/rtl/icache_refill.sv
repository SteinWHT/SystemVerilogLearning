// Line refill engine (read-only).
//
// Streams a full cache line as MEM_WORDS_PER_LINE sequential 64-bit beats over
// a simple req/ack memory bus.  One outstanding beat at a time; mem_ack
// advances the beat counter.

module icache_refill (
    input  logic                       clk,
    input  logic                       rst_n,

    input  logic                       start_read,
    input  icache_pkg::mem_idx_t       base_widx,

    output logic                       busy,
    output logic                       done,
    output icache_pkg::cache_line_t    read_line,

    output logic                       mem_req,
    output logic                       mem_we,
    output icache_pkg::mem_idx_t       mem_idx,
    output icache_pkg::mem_word_t      mem_wdata,
    input  icache_pkg::mem_word_t      mem_rdata,
    input  logic                       mem_ack
);
    import icache_pkg::*;

    localparam int unsigned BEAT_BITS = $clog2(MEM_WORDS_PER_LINE);

    typedef enum logic [1:0] {
        RF_IDLE = 2'b00,
        RF_REQ  = 2'b01,
        RF_DONE = 2'b10
    } rf_state_e;

    rf_state_e            state_q;
    logic [BEAT_BITS-1:0] beat_q;
    mem_idx_t             base_q;
    cache_line_t          line_q;

    assign busy      = (state_q != RF_IDLE);
    assign done      = (state_q == RF_DONE);
    assign read_line = line_q;

    assign mem_req   = (state_q == RF_REQ);
    assign mem_we    = 1'b0;
    assign mem_idx   = base_q + mem_idx_t'(beat_q);
    assign mem_wdata = '0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q <= RF_IDLE;
            beat_q  <= '0;
            base_q  <= '0;
            line_q  <= '0;
        end else begin
            unique case (state_q)
                RF_IDLE: begin
                    if (start_read) begin
                        beat_q  <= '0;
                        base_q  <= base_widx;
                        state_q <= RF_REQ;
                    end
                end
                RF_REQ: begin
                    if (mem_ack) begin
                        line_q[int'(beat_q)*MEM_WORD_BITS +: MEM_WORD_BITS] <= mem_rdata;
                        if (beat_q == BEAT_BITS'(MEM_WORDS_PER_LINE-1))
                            state_q <= RF_DONE;
                        else
                            beat_q <= beat_q + 1'b1;
                    end
                end
                RF_DONE: begin
                    state_q <= RF_IDLE;
                end
                default: state_q <= RF_IDLE;
            endcase
        end
    end

endmodule
