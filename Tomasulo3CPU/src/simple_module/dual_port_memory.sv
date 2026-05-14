// dual port memory
// Writes: registered (committed at clock edge)
// Reads:  combinational (available same cycle)
//   READBEFOREWRITE=1 → read always sees the pre-write value
//   READBEFOREWRITE=0 → read sees forwarded write data when same address
module dual_port_memory #(
    parameter int unsigned DATA_WIDTH = 8,
    parameter int unsigned DEPTH = 8,
    parameter int unsigned ADDR_WIDTH = $clog2(DEPTH),
    parameter int unsigned READBEFOREWRITE = 0
) (
    input logic clk,
    input logic rst_n,
    input logic [DATA_WIDTH-1:0] data_in_a,
    input logic [DATA_WIDTH-1:0] data_in_b,
    input logic write_en_a,
    input logic write_en_b,
    input logic read_en_a,
    input logic read_en_b,
    input logic [ADDR_WIDTH-1:0] address_a,
    input logic [ADDR_WIDTH-1:0] address_b,
    output logic [DATA_WIDTH-1:0] data_out_a,
    output logic [DATA_WIDTH-1:0] data_out_b
);

    logic [DATA_WIDTH-1:0] memory_data [DEPTH];

    // Writes: registered
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            memory_data <= '{default: 0};
        end else begin
            if (write_en_a && write_en_b && address_a == address_b)
                memory_data[address_a] <= data_in_a;
            else begin
                if (write_en_a) memory_data[address_a] <= data_in_a;
                if (write_en_b) memory_data[address_b] <= data_in_b;
            end
        end
    end

    // Reads: combinational
    always_comb begin
        data_out_a = '0;
        data_out_b = '0;

        if (READBEFOREWRITE) begin
            if (read_en_a) data_out_a = memory_data[address_a];
            if (read_en_b) data_out_b = memory_data[address_b];
        end else begin
            if (read_en_a) begin
                if (write_en_b && address_b == address_a)
                    data_out_a = data_in_b;
                else
                    data_out_a = memory_data[address_a];
            end
            if (read_en_b) begin
                if (write_en_a && address_a == address_b)
                    data_out_b = data_in_a;
                else
                    data_out_b = memory_data[address_b];
            end
        end
    end

    // synthesis translate_off
    always_ff @(posedge clk) begin
        if(rst_n)
            DUAL_PORT_MEMORY: assert(!((write_en_a && write_en_b) && (address_a == address_b)))
            else $warning("write a and b to the same address cannot be enabled at the same time");
    end
    // synthesis translate_on
endmodule
