package axi_pkg;

    localparam int unsigned AXI_ADDR_WIDTH  = 32;
    localparam int unsigned AXI_DATA_WIDTH  = 64;
    localparam int unsigned AXI_ID_WIDTH    = 4;
    localparam int unsigned AXI_LEN_WIDTH   = 8;
    localparam int unsigned AXI_SIZE_WIDTH  = 3;
    localparam int unsigned AXI_BURST_WIDTH = 2;

    typedef logic [63:0] axi_addr_max_t;

    typedef enum logic [1:0] {
        AXI_RESP_OKAY   = 2'b00,
        AXI_RESP_EXOKAY = 2'b01,
        AXI_RESP_SLVERR = 2'b10,
        AXI_RESP_DECERR = 2'b11
    } axi_resp_e;

    typedef enum logic [1:0] {
        AXI_BURST_FIXED = 2'b00,
        AXI_BURST_INCR  = 2'b01,
        AXI_BURST_WRAP  = 2'b10
    } axi_burst_e;

    function automatic bit is_power_of_two(input int unsigned value);
        return (value != 0) && ((value & (value - 1)) == 0);
    endfunction

    function automatic int unsigned byte_lsb(input int unsigned data_width);
        return $clog2(data_width / 8);
    endfunction

    function automatic int unsigned bytes_per_beat(
        input logic [AXI_SIZE_WIDTH-1:0] axsize
    );
        return 1 << axsize;
    endfunction

    function automatic int unsigned burst_beats(
        input logic [AXI_LEN_WIDTH-1:0] axlen
    );
        return int'(axlen) + 1;
    endfunction

    function automatic bit wrap_len_legal(
        input logic [AXI_LEN_WIDTH-1:0] axlen
    );
        int unsigned beats;
        beats = burst_beats(axlen);
        return (beats == 2) || (beats == 4) || (beats == 8) || (beats == 16);
    endfunction

    function automatic bit addr_aligned_to_size(
        input axi_addr_max_t                    addr,
        input logic [AXI_SIZE_WIDTH-1:0]        axsize
    );
        axi_addr_max_t mask;
        mask = axi_addr_max_t'(bytes_per_beat(axsize));
        mask = mask - 1;
        return (addr & mask) == '0;
    endfunction

    function automatic axi_addr_max_t burst_next_addr(
        input axi_addr_max_t                    addr,
        input logic [AXI_LEN_WIDTH-1:0]         axlen,
        input logic [AXI_SIZE_WIDTH-1:0]        axsize,
        input logic [AXI_BURST_WIDTH-1:0]       axburst
    );
        axi_addr_max_t beat_bytes;
        axi_addr_max_t wrap_bytes;
        axi_addr_max_t wrap_base;
        axi_addr_max_t next_addr;

        beat_bytes = axi_addr_max_t'(bytes_per_beat(axsize));
        next_addr  = addr + beat_bytes;

        case (axburst)
            AXI_BURST_FIXED: burst_next_addr = addr;
            AXI_BURST_INCR:  burst_next_addr = next_addr;
            AXI_BURST_WRAP: begin
                wrap_bytes = axi_addr_max_t'(burst_beats(axlen) *
                                             bytes_per_beat(axsize));
                wrap_base  = (addr / wrap_bytes) * wrap_bytes;
                if (next_addr >= (wrap_base + wrap_bytes))
                    burst_next_addr = wrap_base;
                else
                    burst_next_addr = next_addr;
            end
            default: burst_next_addr = addr;
        endcase
    endfunction

    function automatic bit burst_crosses_4k(
        input axi_addr_max_t                    addr,
        input logic [AXI_LEN_WIDTH-1:0]         axlen,
        input logic [AXI_SIZE_WIDTH-1:0]        axsize,
        input logic [AXI_BURST_WIDTH-1:0]       axburst
    );
        axi_addr_max_t cur;
        axi_addr_max_t beat_end;
        axi_addr_max_t page;
        int unsigned beats;

        cur   = addr;
        page  = addr >> 12;
        beats = burst_beats(axlen);
        for (int i = 0; i < beats; i++) begin
            beat_end = cur + axi_addr_max_t'(bytes_per_beat(axsize)) - 1;
            if ((cur >> 12) != page || (beat_end >> 12) != page)
                return 1'b1;
            cur = burst_next_addr(cur, axlen, axsize, axburst);
        end
        return 1'b0;
    endfunction

    function automatic bit burst_addr_in_range(
        input axi_addr_max_t                    addr,
        input logic [AXI_LEN_WIDTH-1:0]         axlen,
        input logic [AXI_SIZE_WIDTH-1:0]        axsize,
        input logic [AXI_BURST_WIDTH-1:0]       axburst,
        input int unsigned                      data_width,
        input int unsigned                      sram_depth
    );
        axi_addr_max_t cur;
        axi_addr_max_t beat_end;
        axi_addr_max_t memory_bytes;
        int unsigned beats;

        cur          = addr;
        beats        = burst_beats(axlen);
        memory_bytes = axi_addr_max_t'(sram_depth) *
                       (axi_addr_max_t'(data_width) / 8);
        for (int i = 0; i < beats; i++) begin
            beat_end = cur + axi_addr_max_t'(bytes_per_beat(axsize));
            if (cur >= memory_bytes || beat_end > memory_bytes)
                return 1'b0;
            cur = burst_next_addr(cur, axlen, axsize, axburst);
        end
        return 1'b1;
    endfunction

    function automatic axi_resp_e check_burst(
        input axi_addr_max_t                    addr,
        input logic [AXI_LEN_WIDTH-1:0]         axlen,
        input logic [AXI_SIZE_WIDTH-1:0]        axsize,
        input logic [AXI_BURST_WIDTH-1:0]       axburst,
        input int unsigned                      data_width,
        input int unsigned                      sram_depth
    );
        if (!is_power_of_two(data_width / 8))
            return AXI_RESP_SLVERR;
        if (bytes_per_beat(axsize) > (data_width / 8))
            return AXI_RESP_SLVERR;
        if (axburst == 2'b11)
            return AXI_RESP_SLVERR;
        if (axburst == AXI_BURST_WRAP && !wrap_len_legal(axlen))
            return AXI_RESP_SLVERR;
        if (!addr_aligned_to_size(addr, axsize))
            return AXI_RESP_SLVERR;
        if (burst_crosses_4k(addr, axlen, axsize, axburst))
            return AXI_RESP_SLVERR;
        if (!burst_addr_in_range(addr, axlen, axsize, axburst,
                                 data_width, sram_depth))
            return AXI_RESP_DECERR;
        return AXI_RESP_OKAY;
    endfunction

    function automatic axi_resp_e merge_resp(
        input axi_resp_e current_resp,
        input axi_resp_e new_resp
    );
        if (current_resp == AXI_RESP_DECERR || new_resp == AXI_RESP_DECERR)
            return AXI_RESP_DECERR;
        if (current_resp == AXI_RESP_SLVERR || new_resp == AXI_RESP_SLVERR)
            return AXI_RESP_SLVERR;
        return current_resp;
    endfunction

endpackage
