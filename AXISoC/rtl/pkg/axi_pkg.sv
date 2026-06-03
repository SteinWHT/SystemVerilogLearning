// Shared types and helpers for AXISoC (AXI4-Lite + full AXI4).

package axi_pkg;

    localparam int unsigned AXI_ADDR_WIDTH  = 32;
    localparam int unsigned AXI_DATA_WIDTH  = 64;
    localparam int unsigned AXI_STRB_WIDTH  = AXI_DATA_WIDTH / 8;
    localparam int unsigned AXI_PROT_WIDTH  = 3;
    localparam int unsigned AXI_LEN_WIDTH   = 8;
    localparam int unsigned AXI_SIZE_WIDTH  = 3;
    localparam int unsigned AXI_BURST_WIDTH = 2;

    localparam int unsigned AXI_PAGE_BYTES  = 4096;

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

    function automatic int unsigned byte_lsb(int unsigned data_width);
        return $clog2(data_width / 8);
    endfunction

    function automatic int unsigned bytes_per_beat(input logic [AXI_SIZE_WIDTH-1:0] axsize);
        return (1 << axsize);
    endfunction

    function automatic bit addr_aligned_to_size(
        input logic [AXI_ADDR_WIDTH-1:0] addr,
        input logic [AXI_SIZE_WIDTH-1:0] axsize
    );
        logic [AXI_ADDR_WIDTH-1:0] mask;
        int unsigned lsb;
        lsb  = axsize;
        mask = (logic'(64'h1) << lsb) - 1;
        return ((addr & mask) == '0);
    endfunction

    function automatic bit addr_aligned(
        input logic [AXI_ADDR_WIDTH-1:0] addr,
        input int unsigned               data_width
    );
        return addr_aligned_to_size(addr, byte_lsb(data_width));
    endfunction

    function automatic bit addr_in_range(
        input logic [AXI_ADDR_WIDTH-1:0] addr,
        input int unsigned               data_width,
        input int unsigned               sram_depth
    );
        int unsigned idx;
        idx = addr_to_idx(addr, data_width);
        return (idx < sram_depth);
    endfunction

    function automatic int unsigned addr_to_idx(
        input logic [AXI_ADDR_WIDTH-1:0] addr,
        input int unsigned               data_width
    );
        return int'(addr >> byte_lsb(data_width));
    endfunction

    function automatic logic [AXI_ADDR_WIDTH-1:0] burst_next_addr(
        input logic [AXI_ADDR_WIDTH-1:0]    addr,
        input logic [AXI_SIZE_WIDTH-1:0]    axsize,
        input logic [AXI_BURST_WIDTH-1:0]   axburst
    );
        if (axburst == 2'b01)
            burst_next_addr = addr + (logic'(1) << axsize);
        else
            burst_next_addr = addr;
    endfunction

    function automatic bit burst_crosses_4k(
        input logic [AXI_ADDR_WIDTH-1:0]    addr,
        input logic [AXI_LEN_WIDTH-1:0]     axlen,
        input logic [AXI_SIZE_WIDTH-1:0]    axsize,
        input logic [AXI_BURST_WIDTH-1:0]   axburst
    );
        logic [AXI_ADDR_WIDTH-1:0] end_addr;
        logic [AXI_ADDR_WIDTH-1:0] cur;
        int unsigned             num_beats;
        int unsigned             num_bytes;
        num_beats = int'(axlen) + 1;
        num_bytes = num_beats * bytes_per_beat(axsize);
        if (num_bytes == 0)
            return 1'b0;
        end_addr = addr + logic'(num_bytes - 1);
        if ((addr >> 12) != (end_addr >> 12))
            return 1'b1;
        // Per-beat start address check (catches INCR crossing at 4KB boundary).
        cur = addr;
        for (int i = 0; i < num_beats; i++) begin
            if ((cur >> 12) != (addr >> 12))
                return 1'b1;
            if (i != num_beats - 1)
                cur = burst_next_addr(cur, axsize, axburst);
        end
        return 1'b0;
    endfunction

    function automatic bit burst_addr_in_range(
        input logic [AXI_ADDR_WIDTH-1:0]    addr,
        input logic [AXI_LEN_WIDTH-1:0]     axlen,
        input logic [AXI_SIZE_WIDTH-1:0]    axsize,
        input logic [AXI_BURST_WIDTH-1:0]   axburst,
        input int unsigned                  data_width,
        input int unsigned                  sram_depth
    );
        logic [AXI_ADDR_WIDTH-1:0] cur;
        cur = addr;
        for (int i = 0; i <= int'(axlen); i++) begin
            if (!addr_in_range(cur, data_width, sram_depth))
                return 1'b0;
            cur = burst_next_addr(cur, axsize, axburst);
        end
        return 1'b1;
    endfunction

    function automatic axi_resp_e check_burst(
        input logic [AXI_ADDR_WIDTH-1:0]    addr,
        input logic [AXI_LEN_WIDTH-1:0]     axlen,
        input logic [AXI_SIZE_WIDTH-1:0]    axsize,
        input logic [AXI_BURST_WIDTH-1:0]   axburst,
        input int unsigned                  data_width,
        input int unsigned                  sram_depth
    );
        if (axburst == 2'b10)
            return AXI_RESP_SLVERR;
        if (axburst != 2'b00 && axburst != 2'b01)
            return AXI_RESP_SLVERR;
        if (bytes_per_beat(axsize) != (data_width / 8))
            return AXI_RESP_SLVERR;
        if (!addr_aligned_to_size(addr, axsize))
            return AXI_RESP_SLVERR;
        if (burst_crosses_4k(addr, axlen, axsize, axburst))
            return AXI_RESP_SLVERR;
        if (!burst_addr_in_range(addr, axlen, axsize, axburst, data_width, sram_depth))
            return AXI_RESP_DECERR;
        return AXI_RESP_OKAY;
    endfunction

endpackage
