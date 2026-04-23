// Asynchronous FIFO (Gray pointers, dual-clock RAM).
// IP-oriented: independent write/read resets, optional almost flags, elaboration checks.

module async_fifo #(
    parameter int unsigned DATA_WIDTH = 8,
    parameter int unsigned ADDR_WIDTH = 8,
    // When 0: almost_full is tied low. Else assert when used >= DEPTH - ALMOST_FULL_GAP (GAP free slots remain).
    parameter int unsigned ALMOST_FULL_GAP = 0,
    // When 0: almost_empty is tied low. Else assert when used <= ALMOST_EMPTY_GAP (inclusive of empty).
    parameter int unsigned ALMOST_EMPTY_GAP = 0
) (
    input  logic                    wclk,
    input  logic                    rclk,
    input  logic                    wr_rst_n,
    input  logic                    rd_rst_n,
    input  logic                    wr_en,
    input  logic [DATA_WIDTH-1:0] wr_data,
    input  logic                    rd_en,
    output logic [DATA_WIDTH-1:0] rd_data,
    output logic                    full,
    output logic                    empty,
    output logic                    almost_full,
    output logic                    almost_empty
);

    localparam int unsigned PTR_WIDTH = ADDR_WIDTH + 1;
    localparam int unsigned DEPTH     = 1 << ADDR_WIDTH;

    // Gray full compare needs PTR_WIDTH >= 3 (ADDR_WIDTH >= 2).
    generate
        if (ADDR_WIDTH < 2) begin : gen_addr_chk
            initial $error("async_fifo: ADDR_WIDTH must be >= 2 (Gray full compare uses [PTR_WIDTH-3:0]).");
        end
    endgenerate
    generate
        if (ALMOST_FULL_GAP != 0 && ALMOST_FULL_GAP >= DEPTH) begin : gen_afull_chk
            initial $error("async_fifo: ALMOST_FULL_GAP (%0d) must be < DEPTH (%0d).", ALMOST_FULL_GAP, DEPTH);
        end
    endgenerate
    generate
        if (ALMOST_EMPTY_GAP != 0 && ALMOST_EMPTY_GAP >= DEPTH) begin : gen_aempty_chk
            initial $error("async_fifo: ALMOST_EMPTY_GAP (%0d) must be < DEPTH (%0d).", ALMOST_EMPTY_GAP, DEPTH);
        end
    endgenerate

    function automatic logic [PTR_WIDTH-1:0] gray_to_bin(input logic [PTR_WIDTH-1:0] g);
        gray_to_bin[PTR_WIDTH-1] = g[PTR_WIDTH-1];
        for (int i = PTR_WIDTH - 2; i >= 0; i--) begin
            gray_to_bin[i] = gray_to_bin[i+1] ^ g[i];
        end
    endfunction

    logic [PTR_WIDTH-1:0] wr_ptr_bin;
    logic [PTR_WIDTH-1:0] wr_ptr_gray;
    logic [PTR_WIDTH-1:0] rd_ptr_bin;
    logic [PTR_WIDTH-1:0] rd_ptr_gray;

    logic [PTR_WIDTH-1:0] rd_sync_ptr_gray;
    logic [PTR_WIDTH-1:0] wr_sync_ptr_gray;

    logic [PTR_WIDTH-1:0] rd_bin_wclk;
    logic [PTR_WIDTH-1:0] wr_bin_rclk;

    assign rd_bin_wclk = gray_to_bin(rd_sync_ptr_gray);
    assign wr_bin_rclk = gray_to_bin(wr_sync_ptr_gray);

    write_ptr_handler #(
        .PTR_WIDTH(PTR_WIDTH)
    ) write_ptr_handler_inst (
        .wclk(wclk),
        .wr_rst_n(wr_rst_n),
        .wr_en(wr_en),
        .rd_sync_ptr_gray(rd_sync_ptr_gray),
        .full(full),
        .wr_ptr_bin(wr_ptr_bin),
        .wr_ptr_gray(wr_ptr_gray)
    );

    read_ptr_handler #(
        .PTR_WIDTH(PTR_WIDTH)
    ) read_ptr_handler_inst (
        .rclk(rclk),
        .rd_rst_n(rd_rst_n),
        .rd_en(rd_en),
        .wr_sync_ptr_gray(wr_sync_ptr_gray),
        .empty(empty),
        .rd_ptr_bin(rd_ptr_bin),
        .rd_ptr_gray(rd_ptr_gray)
    );

    synchronizer #(
        .WIDTH(PTR_WIDTH)
    ) wr_sync_ptr_gray_synchronizer_inst (
        .clk(rclk),
        .rst_n(rd_rst_n),
        .async_in(wr_ptr_gray),
        .sync_out(wr_sync_ptr_gray)
    );

    synchronizer #(
        .WIDTH(PTR_WIDTH)
    ) rd_sync_ptr_gray_synchronizer_inst (
        .clk(wclk),
        .rst_n(wr_rst_n),
        .async_in(rd_ptr_gray),
        .sync_out(rd_sync_ptr_gray)
    );

    memory #(
        .DATA_WIDTH(DATA_WIDTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) memory_inst (
        .wclk(wclk),
        .rclk(rclk),
        .wr_rst_n(wr_rst_n),
        .rd_rst_n(rd_rst_n),
        .rd_data(rd_data),
        .rd_addr(rd_ptr_bin[ADDR_WIDTH-1:0]),
        .rd_en(rd_en),
        .wr_data(wr_data),
        .wr_addr(wr_ptr_bin[ADDR_WIDTH-1:0]),
        .wr_en(wr_en),
        .full(full),
        .empty(empty)
    );

    // Registered; thresholds are approximate (pointer sync latency on the other clock).
    always_ff @(posedge wclk or negedge wr_rst_n) begin
        if (!wr_rst_n) begin
            almost_full <= 1'b0;
        end else begin
            almost_full <= (ALMOST_FULL_GAP != 0) &&
                ((wr_ptr_bin - rd_bin_wclk) >= PTR_WIDTH'(DEPTH - ALMOST_FULL_GAP));
        end
    end

    always_ff @(posedge rclk or negedge rd_rst_n) begin
        if (!rd_rst_n) begin
            almost_empty <= 1'b0;
        end else begin
            almost_empty <= (ALMOST_EMPTY_GAP != 0) &&
                ((wr_bin_rclk - rd_ptr_bin) <= PTR_WIDTH'(ALMOST_EMPTY_GAP));
        end
    end

endmodule
