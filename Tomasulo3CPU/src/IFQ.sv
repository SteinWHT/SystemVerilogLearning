`timescale 1ns/1ps

// 4-way interleaved fetch queue
// n * INSTR_WIDTH bit in (n <= NUM_WAYS)
// 1 * INSTR_WIDTH bit out
// Assume I-CACHE can only read n instructions at a time
// Therefore, INSTR_WIDTH can be different from IMEM_WIDTH
// I try to design this module in a way that is easy to extend to more ways
// but in cost of more logic and area
module IFQ #(
    parameter int unsigned INSTR_WIDTH = 32,
    parameter int unsigned IMEM_DEPTH = 64,
    parameter int unsigned IMEM_WIDTH = 32,
    parameter int unsigned IMEM_WIDTH_WORD = IMEM_DEPTH - 1,
    parameter int unsigned DEPTH = 16,
    parameter int unsigned NUM_WAYS = 4
) (
    input  logic                        clk,
    input  logic                        rst_n,

    // I-CACHE interface
    input  logic [IMEM_WIDTH-1:0]       imem_data,
    input  logic                        imem_valid,

    output logic [IMEM_DEPTH-1:0]       imem_addr,
    output logic                        imem_read_rdy,

    // DISPATCH interface
    input  logic                        dis_ren,
    input  logic                        dis_jmpbr,
    input  logic [IMEM_WIDTH_WORD-1:0]  dis_jmpbr_addr,
    input  logic                        dis_jmpbr_addr_valid,

    output logic [INSTR_WIDTH-1:0]      ifq_instr_out,
    output logic [IMEM_DEPTH-1:0]       ifq_pc,
    output logic [IMEM_DEPTH-1:0]       ifq_pc_plus4,
    output logic                        ifq_empty
);

    localparam int unsigned NumWaysWidth = $clog2(NUM_WAYS);
    localparam int unsigned OneWayDepth = DEPTH / NUM_WAYS;
    localparam int unsigned OneTimeInstrNum = IMEM_WIDTH / INSTR_WIDTH;
    localparam int unsigned InstrBytes = INSTR_WIDTH / 8;

    // Per-FIFO status signals
    logic [NUM_WAYS-1:0] empty_array;
    logic [NUM_WAYS-1:0] full_array;

    // Per-FIFO write/read enables and data routing
    logic [NUM_WAYS-1:0]    write_en_array;
    logic [NUM_WAYS-1:0]    read_en_array;
    logic [INSTR_WIDTH-1:0] data_in_array [NUM_WAYS];
    logic [INSTR_WIDTH-1:0] instr_out_array [NUM_WAYS];

    // Round-robin way pointers
    logic [NumWaysWidth-1:0] wr_way;
    logic [NumWaysWidth-1:0] rd_way;

    logic full, empty, flush;

    logic [IMEM_DEPTH-1:0] pc;
    logic [IMEM_DEPTH-1:0] pc_plus4;
    logic [IMEM_DEPTH-1:0] imem_pc;

    assign flush   = dis_jmpbr && dis_jmpbr_addr_valid;
    assign pc_plus4 = pc + IMEM_DEPTH'(InstrBytes);

    // full: any FIFO is full
    logic [NUM_WAYS-1:0] wr_target_mask;
    always_comb begin
        wr_target_mask = '0;
        for (int i = 0; i < OneTimeInstrNum; i++)
            wr_target_mask[NumWaysWidth'(wr_way + i[NumWaysWidth-1:0])] = 1'b1;
    end

    assign full  = |(wr_target_mask & full_array);
    assign empty = empty_array[rd_way];

    // Compute per-FIFO write enables and data routing
    always_comb begin
        write_en_array = '0;
        read_en_array  = '0;
        data_in_array  = '{default: '0};

        for (int i = 0; i < OneTimeInstrNum; i++) begin
            automatic logic [NumWaysWidth-1:0] target;
            target = wr_way + NumWaysWidth'(i);
            write_en_array[target] = imem_valid && !full && !dis_jmpbr;
            data_in_array[target]  = imem_data[i * INSTR_WIDTH +: INSTR_WIDTH];
        end

        read_en_array[rd_way] = dis_ren && !empty && !dis_jmpbr;
    end

    // Sub-FIFOs
    genvar gi;
    generate
        for (gi = 0; gi < NUM_WAYS; gi++) begin: g_way_fifo_inst
            sync_fifo #(
                .DATA_WIDTH(INSTR_WIDTH),
                .DEPTH(OneWayDepth)
            ) sync_fifo_inst (
                .clk(clk),
                .rst_n(rst_n),
                .clear(flush),
                .data_in(data_in_array[gi]),
                .write_en(write_en_array[gi]),
                .read_en(read_en_array[gi]),
                .data_out(instr_out_array[gi]),
                .empty(empty_array[gi]),
                .full(full_array[gi])
            );
        end
    endgenerate

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rd_way  <= '0;
            wr_way  <= '0;
            pc      <= '0;
            imem_pc <= '0;
        end else begin
            if (dis_jmpbr) begin
                if (dis_jmpbr_addr_valid) begin
                    rd_way  <= '0;
                    wr_way  <= '0;
                    imem_pc <= {dis_jmpbr_addr, 1'b0};
                    pc      <= {dis_jmpbr_addr, 1'b0};
                end
            end else begin
                if (imem_valid && !full) begin
                    wr_way  <= wr_way + NumWaysWidth'(OneTimeInstrNum);
                    imem_pc <= imem_pc + IMEM_DEPTH'(OneTimeInstrNum * (InstrBytes));
                end

                if (dis_ren && !empty) begin
                    pc     <= pc_plus4;
                    rd_way <= rd_way + 1'b1;
                end
            end
        end
    end

    assign ifq_instr_out = instr_out_array[rd_way];
    assign ifq_empty     = empty;
    assign ifq_pc        = pc;
    assign ifq_pc_plus4  = pc_plus4;
    assign imem_addr     = imem_pc;
    assign imem_read_rdy = !full && !dis_jmpbr;

    // synthesis translate_off
    initial begin
        IFQ_MAX_INSTR_NUM_ASSERTIONL: assert (OneTimeInstrNum <= NUM_WAYS)
            else $error("IFQ: OneTimeInstrNum > NUM_WAYS");
        IFQ_DEPTH_ASSERTION: assert (DEPTH % NUM_WAYS == 0)
            else $error("IFQ: DEPTH %% NUM_WAYS != 0");
        IFQ_POWER_OF_2_ASSERTION: assert ((NUM_WAYS & (NUM_WAYS - 1)) == 0)
            else $error("IFQ: NUM_WAYS must be a power of 2");
    end
    // synthesis translate_on

endmodule
