// Free List Register
// physical register file [0:127]
// 0-31: architectural registers
// 32-127: physical registers
// represent the pyhsical register file index [32:127]
// No too small assertion
`timescale 1ns/1ps
module FRL #(
    parameter int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    parameter int unsigned ARCH_REG_COUNT = 32,
    parameter int unsigned FRL_SIZE = 2**PHY_REGISTER_FILE_WIDTH - ARCH_REG_COUNT,
    parameter int unsigned FRL_PTR_WIDTH = $clog2(FRL_SIZE)
) (
    input  logic clk,
    input  logic rst_n,

    input  logic [PHY_REGISTER_FILE_WIDTH - 1:0]rob_commit_pre_phy_addr,
    input  logic                                rob_commit,
    input  logic                                rob_commit_reg_write,

    input  logic [FRL_PTR_WIDTH:0]              frat_frl_head_ptr,

    input  logic                                cdb_flush,

    input  logic                                dis_frl_read,
    output logic [PHY_REGISTER_FILE_WIDTH - 1:0]frl_read_phy_addr,
    output logic                                frl_read_empty,

    output logic [FRL_PTR_WIDTH:0]              frl_head_ptr_to_frat
);

    logic [FRL_PTR_WIDTH:0] head_ptr, tail_ptr;
    logic empty, full;
    logic do_read, do_write;
    logic [PHY_REGISTER_FILE_WIDTH-1:0] frl_array [FRL_SIZE];

    function automatic logic [FRL_PTR_WIDTH:0] ptr_next(
        input logic [FRL_PTR_WIDTH:0] ptr
    );
        if (ptr[FRL_PTR_WIDTH-1:0] == FRL_PTR_WIDTH'(FRL_SIZE - 1)) begin
            ptr_next = {~ptr[FRL_PTR_WIDTH], {FRL_PTR_WIDTH{1'b0}}};
        end else begin
            ptr_next = ptr + 1'b1;
        end
    endfunction

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            head_ptr <= '0;
            tail_ptr <= {1'b1, {FRL_PTR_WIDTH{1'b0}}};
            for (int i = 0; i < FRL_SIZE; i++) begin
                // initialize with physical register indices
                frl_array[i] <= PHY_REGISTER_FILE_WIDTH'(ARCH_REG_COUNT + i);
            end
        end else begin
            if (do_write) begin
                // On commit, add the freed physical register back to the free list
                frl_array[tail_ptr[FRL_PTR_WIDTH-1:0]] <= rob_commit_pre_phy_addr;
                tail_ptr <= ptr_next(tail_ptr);
            end

            if(cdb_flush) begin
                // On flush, we might need to restore the head pointer from CFC
                head_ptr <= frat_frl_head_ptr;
            end else if (do_read) begin
                // On read, provide the next free physical register and move head pointer
                frl_read_phy_addr <= frl_array[head_ptr[FRL_PTR_WIDTH-1:0]];
                head_ptr <= ptr_next(head_ptr);
            end
        end
    end

    assign empty = (head_ptr == tail_ptr);
    assign full = (head_ptr[FRL_PTR_WIDTH] != tail_ptr[FRL_PTR_WIDTH]) &&
                  (head_ptr[FRL_PTR_WIDTH-1:0] == tail_ptr[FRL_PTR_WIDTH-1:0]);

    assign do_read = dis_frl_read && !empty && !cdb_flush;
    assign do_write = rob_commit && rob_commit_reg_write && (!full || do_read);

    assign frl_read_empty = empty;

    assign frl_head_ptr_to_frat = head_ptr;

    // synthesis translate_off
    always_ff @(posedge clk) begin
        if (rst_n) begin
            FRL_UNDERFLOW: assert (!(do_read && empty))
                            else $error("FRL underflow at time %0t", $time);
            FRL_OVERFLOW: assert (!(do_write && full && !do_read))
                            else $error("FRL overflow at time %0t", $time);
        end
    end
    // synthesis translate_on
endmodule
