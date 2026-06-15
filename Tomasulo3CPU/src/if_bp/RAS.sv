module RAS
    import riscv_btb_pkg::*;
#(
    parameter int unsigned XLEN      = 64,
    parameter int unsigned DEPTH     = 16,
    parameter int unsigned CKPT_NUM  = 8,

    localparam int unsigned PTR_BITS  = (DEPTH > 1) ? $clog2(DEPTH) : 1,
    localparam int unsigned CNT_BITS  = $clog2(DEPTH + 1),
    localparam int unsigned CKPT_BITS = (CKPT_NUM > 1) ? $clog2(CKPT_NUM) : 1
)(
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic                    pred_req_i,
    output logic                    pred_valid_o,
    output logic [XLEN-1:0]         pred_target_o,

    input  logic                    spec_valid_i,
    input  ras_op_e                 spec_op_i,
    input  logic [XLEN-1:0]         spec_return_addr_i,

    input  logic                    ckpt_alloc_i,
    output logic [CKPT_BITS-1:0]    ckpt_id_o,

    input  logic                    restore_i,
    input  logic [CKPT_BITS-1:0]    restore_id_i,

    input  logic                    flush_i
);

    logic [XLEN-1:0] stack [DEPTH];
    logic [PTR_BITS-1:0] sp;
    logic [CNT_BITS-1:0] count;

    logic [PTR_BITS-1:0] ckpt_sp    [CKPT_NUM];
    logic [CNT_BITS-1:0] ckpt_count [CKPT_NUM];
    logic [XLEN-1:0]     ckpt_stack [CKPT_NUM][DEPTH];
    logic [CKPT_BITS-1:0] ckpt_alloc_ptr;

    assign ckpt_id_o = ckpt_alloc_ptr;

    function automatic logic [PTR_BITS-1:0] ptr_inc(
        input logic [PTR_BITS-1:0] ptr
    );
        if (ptr == PTR_BITS'(DEPTH - 1))
            ptr_inc = '0;
        else
            ptr_inc = ptr + PTR_BITS'(1);
    endfunction

    function automatic logic [PTR_BITS-1:0] ptr_dec(
        input logic [PTR_BITS-1:0] ptr
    );
        if (ptr == '0)
            ptr_dec = PTR_BITS'(DEPTH - 1);
        else
            ptr_dec = ptr - PTR_BITS'(1);
    endfunction

    function automatic logic [CKPT_BITS-1:0] ckpt_inc(
        input logic [CKPT_BITS-1:0] ptr
    );
        if (ptr == CKPT_BITS'(CKPT_NUM - 1))
            ckpt_inc = '0;
        else
            ckpt_inc = ptr + CKPT_BITS'(1);
    endfunction

    logic [PTR_BITS-1:0] top_ptr;
    logic [PTR_BITS-1:0] pop_sp;
    logic [CNT_BITS-1:0] pop_count;

    assign top_ptr = ptr_dec(sp);

    always_comb begin
        pred_valid_o  = pred_req_i && (count != '0);
        pred_target_o = '0;
        if (pred_valid_o)
            pred_target_o = stack[top_ptr];
    end

    always_comb begin
        pop_sp    = sp;
        pop_count = count;
        if (count != '0) begin
            pop_sp    = ptr_dec(sp);
            pop_count = count - CNT_BITS'(1);
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sp             <= '0;
            count          <= '0;
            ckpt_alloc_ptr <= '0;

            for (int i = 0; i < DEPTH; i++)
                stack[i] <= '0;

            for (int c = 0; c < CKPT_NUM; c++) begin
                ckpt_sp[c]    <= '0;
                ckpt_count[c] <= '0;
                for (int i = 0; i < DEPTH; i++)
                    ckpt_stack[c][i] <= '0;
            end
        end else if (flush_i) begin
            sp             <= '0;
            count          <= '0;
            ckpt_alloc_ptr <= '0;
        end else begin
            if (ckpt_alloc_i) begin
                ckpt_sp[ckpt_alloc_ptr]    <= sp;
                ckpt_count[ckpt_alloc_ptr] <= count;
                for (int i = 0; i < DEPTH; i++)
                    ckpt_stack[ckpt_alloc_ptr][i] <= stack[i];
                ckpt_alloc_ptr <= ckpt_inc(ckpt_alloc_ptr);
            end

            if (restore_i) begin
                sp    <= ckpt_sp[restore_id_i];
                count <= ckpt_count[restore_id_i];
                for (int i = 0; i < DEPTH; i++)
                    stack[i] <= ckpt_stack[restore_id_i][i];
            end else if (spec_valid_i) begin
                unique case (spec_op_i)
                    RAS_OP_PUSH: begin
                        stack[sp] <= spec_return_addr_i;
                        sp        <= ptr_inc(sp);
                        if (count != CNT_BITS'(DEPTH))
                            count <= count + CNT_BITS'(1);
                    end

                    RAS_OP_POP: begin
                        sp    <= pop_sp;
                        count <= pop_count;
                    end

                    RAS_OP_POP_PUSH: begin
                        stack[pop_sp] <= spec_return_addr_i;
                        sp            <= ptr_inc(pop_sp);
                        if (pop_count != CNT_BITS'(DEPTH))
                            count <= pop_count + CNT_BITS'(1);
                        else
                            count <= pop_count;
                    end

                    default: begin
                        sp    <= sp;
                        count <= count;
                    end
                endcase
            end
        end
    end

    // synthesis translate_off
    initial begin
        assert (DEPTH > 0)
            else $fatal(1, "RAS: DEPTH must be greater than zero");
        assert (CKPT_NUM > 0)
            else $fatal(1, "RAS: CKPT_NUM must be greater than zero");
    end
    // synthesis translate_on

endmodule
