`timescale 1ns/1ps
// only support 2^N entries
module sync_lifo #(
    parameter int unsigned DATA_WIDTH = 8,
    parameter int unsigned DEPTH = 8,
    parameter int unsigned PTR_WIDTH = $clog2(DEPTH),
    // If 1, when full, the next push will overwrite the top entry (circular buffer behavior).
    // If 0, push is ignored when full.
    parameter int unsigned ROUND_ROBIN = 0,
    // If 1, when empty, the next pop will not underflow but keep the top pointer at 0 (no negative index).
    // If 0, pop is ignored when empty.
    parameter int unsigned UNDERFLOW_PROTECT = 0,
    // If 1, when both push and pop are asserted in the same cycle, the behavior is defined as follows:
    // - If the LIFO is empty, the push will be ignored and
    // the pop will take effect, it will pop the latest pushed data and keep the top pointer at 0
    // - If the LIFO is full, push will be ignored and pop will take effect, it will pop the top entry and keep the top pointer at DEPTH
    // - If the LIFO is neither full nor empty, push and pop will both take
    // If 0, when both push and pop are asserted, we will prioritize push and ignore pop (treat it as a no-op for the pointer)
    parameter int unsigned ALLOW_PUSH_POP_SAME_CYCLE = 0
) (
    input  logic clk,
    input  logic rst_n,
    input  logic push,
    input  logic pop,
    input  logic [DATA_WIDTH-1:0] data_in,
    output logic [DATA_WIDTH-1:0] data_out,
    output logic empty,
    output logic full
);
    logic [DATA_WIDTH-1:0] lifo_array [DEPTH];
    logic [PTR_WIDTH:0] top_ptr;
    // For ROUND_ROBIN, we can allow the top_ptr to wrap around and use the full range of indices.
    logic [PTR_WIDTH:0] top_entry_index;
    logic [DATA_WIDTH-1:0] last_pop_data; // to hold the last popped data for underflow protection

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            top_ptr <= 0;
            data_out <= 'hDEAD_BEEF; // invalid value for debugging
            top_entry_index <= DEPTH;
            last_pop_data <= 'hDEAD_BEEF;
        end else if (push && !pop) begin
            if(ROUND_ROBIN && full) begin
                // Power-of-2 DEPTH: ring write at logical top (avoids out-of-range index)
                lifo_array[(top_ptr) & (DEPTH - 1)] <= data_in;
                top_ptr <= top_ptr + 1;
                top_entry_index <= top_entry_index + 1; // move the top entry index up
            end else if(!ROUND_ROBIN && full) begin
                data_out <= 'hDEAD_BEEF;
            end else begin
                lifo_array[top_ptr] <= data_in;
                top_ptr <= top_ptr + 1;
                data_out <= data_in;
            end
        end else if (pop && !push) begin
            if(UNDERFLOW_PROTECT && empty) begin
                data_out <= last_pop_data; // keep the last popped data when underflow
            end else if(empty) begin
                data_out <= 'hDEAD_BEEF; // underflow case, output invalid value for debugging
            end else begin
                // store the popped data for potential underflow protection
                last_pop_data <= lifo_array[(top_ptr - 1) & (DEPTH - 1)];
                data_out <= lifo_array[(top_ptr - 1) & (DEPTH - 1)]; // output the popped data
                top_ptr <= top_ptr - 1; // move the top pointer down
            end
        end else if (push && pop) begin
            if (ALLOW_PUSH_POP_SAME_CYCLE) begin
                data_out <= data_in;
            end else begin
                // Here we choose to prioritize push.
                // Even when push is executed, pop will still be ignored
                if(ROUND_ROBIN && full) begin
                    lifo_array[(top_ptr) & (DEPTH - 1)] <= data_in;
                    top_ptr <= top_ptr + 1;
                    top_entry_index <= top_entry_index + 1; // move the top entry index up
                end else if(!ROUND_ROBIN && full) begin
                    data_out <= 'hDEAD_BEEF;
                end else begin
                    lifo_array[top_ptr] <= data_in;
                    top_ptr <= top_ptr + 1;
                    data_out <= data_in;
                end
            end
        end
    end

    // LIFO is empty when top pointer is at 0
    assign empty = ((top_ptr[PTR_WIDTH-1:0] == top_entry_index[PTR_WIDTH-1:0]) &&
    (top_ptr[PTR_WIDTH] == !top_entry_index[PTR_WIDTH]));
    assign full = (top_ptr == top_entry_index);
endmodule
