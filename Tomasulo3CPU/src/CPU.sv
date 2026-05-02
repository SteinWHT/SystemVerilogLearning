// Top module for the CPU
module CPU #(
    parameter int unsigned INSTRUCTION_WIDTH = 64,
    parameter int unsigned PC_WIDTH = 64,
    parameter int unsigned IFQ_FIFO_DEPTH = 16,
    parameter int unsigned NUM_WAYS = 4,
    parameter int unsigned NUM_WAYS_WIDTH = $clog2(NUM_WAYS)
) (
    input  logic clk,
    input  logic rst_n,
    input  logic [PC_WIDTH + 2 -1:0]        IMEM_address,
    input  logic                            IMEM_valid_in,
    input  logic [INSTRUCTION_WIDTH-1:0]    IMEM_data_in [0:NUM_WAYS-1],
    output logic                            IMEM_valid_out,
);
    logic flush, IFQ_full, IFQ_empty;
    logic [NUM_WAYS_WIDTH-1:0] valid_out;
    logic [INSTRUCTION_WIDTH-1:0] instr_out;
    logic [PC_WIDTH-1:0] pc;

    IFQ #(
        .IN_WIDTH(INSTRUCTION_WIDTH),
        .OUT_WIDTH(INSTRUCTION_WIDTH),
        .DEPTH(IFQ_FIFO_DEPTH),
        .NUM_WAYS(NUM_WAYS),
        .NUM_WAYS_WIDTH(NUM_WAYS_WIDTH)
    ) ifq_inst (
        .clk(clk),
        .rst_n(rst_n),
        .instr_in(IMEM_data_in),
        .valid_in(IMEM_valid_in),
        .flush(flush),
        .valid_out(valid_out),
        .instr_out(instr_out),

        .full(IFQ_full),
        .empty(IFQ_empty)
    );

    assign IMEM_valid_out = !IFQ_full;
    assign IMEM_address   = {pc, 2'b0};

    always_ff @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            pc <= '0;
        end else begin
            if(!IFQ_full) begin
                pc <= pc + 4;
            end
        end
    end



endmodule