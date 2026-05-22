module pseudo_ddr #(
    parameter ADDR_WIDTH = 64,
    parameter DATA_WIDTH = 64,
    parameter DEPTH      = 1024,
    parameter LATENCY    = 5
) (
    input  logic clk,
    input  logic rst_n,

    // Request
    input  logic                  mem_valid,
    output logic                  mem_ready,
    input  logic                  mem_write,
    input  logic [ADDR_WIDTH-1:0] mem_addr,
    input  logic [DATA_WIDTH-1:0] mem_wdata,
    input  logic [DATA_WIDTH/8-1:0] mem_wstrb,

    // Response
    output logic                  mem_resp_valid,
    input  logic                  mem_resp_ready,
    output logic [DATA_WIDTH-1:0] mem_rdata,
    output logic                  mem_resp_error
);

    localparam STRB_WIDTH = DATA_WIDTH / 8;
    localparam IDX_WIDTH  = $clog2(DEPTH);

    logic [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    typedef enum logic [1:0] {
        IDLE,
        WAIT,
        RESP
    } state_t;

    state_t state;

    logic                  req_write_q;
    logic [ADDR_WIDTH-1:0] req_addr_q;
    logic [DATA_WIDTH-1:0] req_wdata_q;
    logic [STRB_WIDTH-1:0] req_wstrb_q;

    logic [$clog2(LATENCY+1)-1:0] count;

    wire [IDX_WIDTH-1:0] word_index;
    assign word_index = req_addr_q[IDX_WIDTH+2:3]; // byte addr -> 64-bit word index

    assign mem_ready = (state == IDLE);

    integer i;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state          <= IDLE;
            mem_resp_valid <= 1'b0;
            mem_rdata      <= '0;
            mem_resp_error <= 1'b0;
            count          <= '0;
        end else begin
            case (state)

                IDLE: begin
                    mem_resp_valid <= 1'b0;
                    mem_resp_error <= 1'b0;

                    if (mem_valid && mem_ready) begin
                        req_write_q <= mem_write;
                        req_addr_q  <= mem_addr;
                        req_wdata_q <= mem_wdata;
                        req_wstrb_q <= mem_wstrb;

                        count <= LATENCY[$clog2(LATENCY+1)-1:0];
                        state <= WAIT;
                    end
                end

                WAIT: begin
                    if (count != 0) begin
                        count <= count - 1'b1;
                    end else begin
                        if (req_write_q) begin
                            for (i = 0; i < STRB_WIDTH; i = i + 1) begin
                                if (req_wstrb_q[i]) begin
                                    mem[word_index][8*i +: 8] <= req_wdata_q[8*i +: 8];
                                end
                            end
                            mem_rdata <= '0;
                        end else begin
                            mem_rdata <= mem[word_index];
                        end

                        mem_resp_valid <= 1'b1;
                        state <= RESP;
                    end
                end

                RESP: begin
                    if (mem_resp_valid && mem_resp_ready) begin
                        mem_resp_valid <= 1'b0;
                        state <= IDLE;
                    end
                end

            endcase
        end
    end

endmodule