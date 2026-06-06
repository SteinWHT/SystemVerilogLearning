module axi_sram #(
    parameter int unsigned ADDR_WIDTH = axi_pkg::AXI_ADDR_WIDTH,
    parameter int unsigned DATA_WIDTH = axi_pkg::AXI_DATA_WIDTH,
    parameter int unsigned ID_WIDTH   = axi_pkg::AXI_ID_WIDTH,
    parameter int unsigned SRAM_DEPTH = 4096
) (
    input  logic clk,
    input  logic rst_n,
    input  logic                  init_en,
    input  logic [ADDR_WIDTH-1:0] init_word_idx,
    input  logic [DATA_WIDTH-1:0] init_data,
    axi_if.slave bus
);

    import axi_pkg::*;

    localparam int unsigned STRB_WIDTH = DATA_WIDTH / 8;
    localparam int unsigned IDX_WIDTH  =
        (SRAM_DEPTH <= 1) ? 1 : $clog2(SRAM_DEPTH);

    logic [DATA_WIDTH-1:0] mem [SRAM_DEPTH];

    logic                  wr_active;
    logic [8:0]            wr_beats_rem;
    logic [ADDR_WIDTH-1:0] wr_addr;
    logic [7:0]            wr_len;
    logic [2:0]            wr_size;
    logic [1:0]            wr_burst;
    logic [ID_WIDTH-1:0]   wr_id;
    axi_resp_e             wr_resp;

    logic                  bvalid_r;
    logic [ID_WIDTH-1:0]   bid_r;
    axi_resp_e             bresp_r;

    logic                  rd_active;
    logic [8:0]            rd_beats_rem;
    logic [ADDR_WIDTH-1:0] rd_addr;
    logic [7:0]            rd_len;
    logic [2:0]            rd_size;
    logic [1:0]            rd_burst;
    logic [ID_WIDTH-1:0]   rd_id;
    axi_resp_e             rd_resp;

    logic                  rvalid_r;
    logic [ID_WIDTH-1:0]   rid_r;
    logic [DATA_WIDTH-1:0] rdata_r;
    axi_resp_e             rresp_r;
    logic                  rlast_r;

    assign bus.awready = rst_n && !init_en && !wr_active && !bvalid_r;
    assign bus.wready  = rst_n && !init_en && wr_active;
    assign bus.bid     = bid_r;
    assign bus.bresp   = bresp_r;
    assign bus.bvalid  = bvalid_r;

    assign bus.arready = rst_n && !init_en && !rd_active && !rvalid_r;
    assign bus.rid     = rid_r;
    assign bus.rdata   = rdata_r;
    assign bus.rresp   = rresp_r;
    assign bus.rlast   = rlast_r;
    assign bus.rvalid  = rvalid_r;

    function automatic logic [IDX_WIDTH-1:0] word_index(
        input logic [ADDR_WIDTH-1:0] addr
    );
        return IDX_WIDTH'(addr >> byte_lsb(DATA_WIDTH));
    endfunction

    function automatic logic [STRB_WIDTH-1:0] transfer_mask(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [2:0]            size
    );
        logic [STRB_WIDTH-1:0] mask;
        int unsigned first_lane;
        int unsigned beat_bytes;

        mask       = '0;
        first_lane = int'(addr) % STRB_WIDTH;
        beat_bytes = bytes_per_beat(size);
        for (int i = 0; i < STRB_WIDTH; i++) begin
            if (i >= first_lane && i < (first_lane + beat_bytes))
                mask[i] = 1'b1;
        end
        return mask;
    endfunction

    function automatic logic [DATA_WIDTH-1:0] read_data(
        input logic [ADDR_WIDTH-1:0] addr,
        input logic [2:0]            size,
        input axi_resp_e             resp
    );
        logic [DATA_WIDTH-1:0] data;
        logic [STRB_WIDTH-1:0] mask;
        logic [IDX_WIDTH-1:0] idx;

        data = '0;
        if (resp == AXI_RESP_OKAY) begin
            idx  = word_index(addr);
            mask = transfer_mask(addr, size);
            for (int i = 0; i < STRB_WIDTH; i++) begin
                if (mask[i])
                    data[8*i +: 8] = mem[idx][8*i +: 8];
            end
        end
        return data;
    endfunction

    initial begin
        if (ADDR_WIDTH > 64)
            $fatal(1, "axi_sram: ADDR_WIDTH must be <= 64");
        if (DATA_WIDTH < 8 || (DATA_WIDTH % 8) != 0 ||
            !is_power_of_two(DATA_WIDTH / 8))
            $fatal(1, "axi_sram: DATA_WIDTH/8 must be a power of two");
        if (ID_WIDTH == 0)
            $fatal(1, "axi_sram: ID_WIDTH must be >= 1");
        if (SRAM_DEPTH == 0)
            $fatal(1, "axi_sram: SRAM_DEPTH must be >= 1");
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wr_active    <= 1'b0;
            wr_beats_rem <= '0;
            wr_addr      <= '0;
            wr_len       <= '0;
            wr_size      <= '0;
            wr_burst     <= '0;
            wr_id        <= '0;
            wr_resp      <= AXI_RESP_OKAY;
            bvalid_r     <= 1'b0;
            bid_r        <= '0;
            bresp_r      <= AXI_RESP_OKAY;

            rd_active    <= 1'b0;
            rd_beats_rem <= '0;
            rd_addr      <= '0;
            rd_len       <= '0;
            rd_size      <= '0;
            rd_burst     <= '0;
            rd_id        <= '0;
            rd_resp      <= AXI_RESP_OKAY;
            rvalid_r     <= 1'b0;
            rid_r        <= '0;
            rdata_r      <= '0;
            rresp_r      <= AXI_RESP_OKAY;
            rlast_r      <= 1'b0;

            if (init_en && (init_word_idx < SRAM_DEPTH))
                mem[IDX_WIDTH'(init_word_idx)] <= init_data;
        end else begin
            if (init_en && (init_word_idx < SRAM_DEPTH))
                mem[IDX_WIDTH'(init_word_idx)] <= init_data;

            if (bvalid_r && bus.bready)
                bvalid_r <= 1'b0;

            if (bus.awvalid && bus.awready) begin
                wr_active    <= 1'b1;
                wr_beats_rem <= {1'b0, bus.awlen} + 9'd1;
                wr_addr      <= bus.awaddr;
                wr_len       <= bus.awlen;
                wr_size      <= bus.awsize;
                wr_burst     <= bus.awburst;
                wr_id        <= bus.awid;
                wr_resp      <= check_burst(
                    axi_addr_max_t'(bus.awaddr), bus.awlen, bus.awsize,
                    bus.awburst, DATA_WIDTH, SRAM_DEPTH
                );
            end

            if (bus.wvalid && bus.wready) begin
                axi_resp_e beat_resp;
                logic [STRB_WIDTH-1:0] legal_mask;
                logic expected_last;
                logic [IDX_WIDTH-1:0] idx;

                beat_resp    = wr_resp;
                legal_mask   = transfer_mask(wr_addr, wr_size);
                expected_last = (wr_beats_rem == 9'd1);

                if (bus.wlast != expected_last)
                    beat_resp = merge_resp(beat_resp, AXI_RESP_SLVERR);
                if (|(bus.wstrb & ~legal_mask))
                    beat_resp = merge_resp(beat_resp, AXI_RESP_SLVERR);

                if (wr_resp == AXI_RESP_OKAY && !init_en) begin
                    idx = word_index(wr_addr);
                    for (int i = 0; i < STRB_WIDTH; i++) begin
                        if (bus.wstrb[i] && legal_mask[i])
                            mem[idx][8*i +: 8] <= bus.wdata[8*i +: 8];
                    end
                end

                if (expected_last) begin
                    wr_active    <= 1'b0;
                    wr_beats_rem <= '0;
                    bvalid_r     <= 1'b1;
                    bid_r        <= wr_id;
                    bresp_r      <= beat_resp;
                end else begin
                    wr_beats_rem <= wr_beats_rem - 9'd1;
                    wr_addr      <= ADDR_WIDTH'(burst_next_addr(
                        axi_addr_max_t'(wr_addr), wr_len, wr_size, wr_burst
                    ));
                    wr_resp <= beat_resp;
                end
            end

            if (bus.arvalid && bus.arready) begin
                axi_resp_e ar_resp;

                ar_resp = check_burst(
                    axi_addr_max_t'(bus.araddr), bus.arlen, bus.arsize,
                    bus.arburst, DATA_WIDTH, SRAM_DEPTH
                );
                rd_active    <= 1'b1;
                rd_beats_rem <= {1'b0, bus.arlen} + 9'd1;
                rd_addr      <= bus.araddr;
                rd_len       <= bus.arlen;
                rd_size      <= bus.arsize;
                rd_burst     <= bus.arburst;
                rd_id        <= bus.arid;
                rd_resp      <= ar_resp;
                rvalid_r     <= 1'b1;
                rid_r        <= bus.arid;
                rdata_r      <= read_data(bus.araddr, bus.arsize, ar_resp);
                rresp_r      <= ar_resp;
                rlast_r      <= (bus.arlen == 8'd0);
            end else if (rvalid_r && bus.rready) begin
                if (rd_beats_rem == 9'd1) begin
                    rd_active    <= 1'b0;
                    rd_beats_rem <= '0;
                    rvalid_r     <= 1'b0;
                    rlast_r      <= 1'b0;
                end else begin
                    logic [ADDR_WIDTH-1:0] next_addr;

                    next_addr = ADDR_WIDTH'(burst_next_addr(
                        axi_addr_max_t'(rd_addr), rd_len, rd_size, rd_burst
                    ));
                    rd_beats_rem <= rd_beats_rem - 9'd1;
                    rd_addr      <= next_addr;
                    rvalid_r     <= 1'b1;
                    rid_r        <= rd_id;
                    rdata_r      <= read_data(next_addr, rd_size, rd_resp);
                    rresp_r      <= rd_resp;
                    rlast_r      <= (rd_beats_rem == 9'd2);
                end
            end
        end
    end

endmodule
