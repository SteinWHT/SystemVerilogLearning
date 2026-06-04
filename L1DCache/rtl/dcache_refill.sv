// Line refill / writeback engine.
//
// Streams a full cache line as WORDS_PER_LINE sequential 64-bit beats over a
// simple req/ack memory bus (industry-style burst on a narrow data path):
//   - start_read : read WORDS_PER_LINE words starting at base_widx into read_line
//   - start_write: write the words of write_line back to memory at base_widx
//
// One outstanding beat at a time; `mem_ack` advances the beat counter

module dcache_refill (
    input  logic                       clk,
    input  logic                       rst_n,

    input  logic                       start_read,
    input  logic                       start_write,
    input  dcache_pkg::mem_idx_t       base_widx,
    input  dcache_pkg::cache_line_t    write_line,

    output logic                       busy,
    output logic                       done,
    output dcache_pkg::cache_line_t    read_line,

    // 64-bit memory bus
    output logic                       mem_req,
    output logic                       mem_we,
    output dcache_pkg::mem_idx_t       mem_idx,
    output dcache_pkg::cache_word_t    mem_wdata,
    input  dcache_pkg::cache_word_t    mem_rdata,
    input  logic                       mem_ack
);
    import dcache_pkg::*;

    localparam int unsigned BEAT_BITS = $clog2(WORDS_PER_LINE);

    typedef enum logic [1:0] {
        RF_IDLE = 2'b00,
        RF_REQ  = 2'b01,   // request asserted, waiting for ack
        RF_DONE = 2'b10    // pulse done for one cycle
    } rf_state_e;

    rf_state_e               state_q;
    logic                    is_write_q;
    logic [BEAT_BITS-1:0]    beat_q;
    mem_idx_t                base_q;
    cache_line_t             line_q;     // write source / read accumulator

    assign busy      = (state_q != RF_IDLE);
    assign done      = (state_q == RF_DONE);
    assign read_line = line_q;

    assign mem_req   = (state_q == RF_REQ);
    assign mem_we    = is_write_q;
    assign mem_idx   = base_q + mem_idx_t'(beat_q);
    assign mem_wdata = line_q[int'(beat_q)*WORD_BITS +: WORD_BITS];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state_q    <= RF_IDLE;
            is_write_q <= 1'b0;
            beat_q     <= '0;
            base_q     <= '0;
            line_q     <= '0;
        end else begin
            unique case (state_q)
                RF_IDLE: begin
                    if (start_read || start_write) begin
                        is_write_q <= start_write;
                        beat_q     <= '0;
                        base_q     <= base_widx;
                        if (start_write)
                            line_q <= write_line;
                        state_q    <= RF_REQ;
                    end
                end
                RF_REQ: begin
                    if (mem_ack) begin
                        if (!is_write_q)
                            line_q[int'(beat_q)*WORD_BITS +: WORD_BITS] <= mem_rdata;
                        if (beat_q == BEAT_BITS'(WORDS_PER_LINE-1))
                            state_q <= RF_DONE;
                        else
                            beat_q  <= beat_q + 1'b1;
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
