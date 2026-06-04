// L1 D-cache parameters and helpers
// Cache configuration:
//   16 KiB, 4-way set-associative, 64-byte lines, write-back / write-allocate
//   CPU access granularity is a 64-bit word with an 8-bit byte strobe
//   A line is refilled / written back as an 8-beat burst on a 64-bit memory bus

package dcache_pkg;

    // Address / data widths
    localparam int unsigned ADDR_WIDTH   = 32;

    // CPU access granularity
    localparam int unsigned WORD_BITS    = 64;
    localparam int unsigned WORD_BYTES    = WORD_BITS / 8;          // 8
    localparam int unsigned STRB_WIDTH    = WORD_BYTES;             // 8

    // Cache line
    localparam int unsigned LINE_BYTES    = 64;
    localparam int unsigned LINE_BITS     = LINE_BYTES * 8;         // 512
    localparam int unsigned WORDS_PER_LINE = LINE_BYTES / WORD_BYTES; // 8

    // Organization
    localparam int unsigned NUM_WAYS      = 4;
    localparam int unsigned NUM_SETS      = 64;                     // 64*4*64B = 16 KiB
    localparam int unsigned CACHE_BYTES   = NUM_SETS * NUM_WAYS * LINE_BYTES;

    // Address decomposition: | tag | index | line-offset |
    //   line-offset = | word-select | byte-in-word |
    localparam int unsigned BYTE_OFF_BITS = $clog2(WORD_BYTES);     // 3  addr[2:0]
    localparam int unsigned WORD_SEL_BITS = $clog2(WORDS_PER_LINE); // 3  addr[5:3]
    localparam int unsigned OFFSET_BITS   = $clog2(LINE_BYTES);     // 6  addr[5:0]
    localparam int unsigned INDEX_BITS    = $clog2(NUM_SETS);       // 6  addr[11:6]
    localparam int unsigned WAY_BITS      = $clog2(NUM_WAYS);       // 2
    localparam int unsigned TAG_BITS      = ADDR_WIDTH - INDEX_BITS - OFFSET_BITS;
    localparam int unsigned PLRU_BITS     = NUM_WAYS - 1;           // 3 (tree PLRU)

    // Backing memory model: word-addressable (64-bit) SRAM.
    // Word address = byte_addr[ADDR_WIDTH-1:BYTE_OFF_BITS]; we keep a modest
    // window so directed tests never alias.  MEM_IDX_BITS words are modelled.
    localparam int unsigned MEM_IDX_BITS  = 16;                     // 64K words = 512 KiB
    localparam int unsigned MEM_DEPTH     = 1 << MEM_IDX_BITS;

    typedef logic [TAG_BITS-1:0]       cache_tag_t;
    typedef logic [INDEX_BITS-1:0]     cache_set_t;
    typedef logic [WAY_BITS-1:0]       cache_way_t;
    typedef logic [WORD_SEL_BITS-1:0]  word_sel_t;
    typedef logic [NUM_WAYS-1:0]       way_mask_t;
    typedef logic [LINE_BITS-1:0]      cache_line_t;
    typedef logic [WORD_BITS-1:0]      cache_word_t;
    typedef logic [ADDR_WIDTH-1:0]     cache_addr_t;
    typedef logic [STRB_WIDTH-1:0]     cache_strb_t;
    typedef logic [PLRU_BITS-1:0]      plru_state_t;
    typedef logic [MEM_IDX_BITS-1:0]   mem_idx_t;

    typedef struct packed {
        logic        valid;
        logic        dirty;
        cache_tag_t  tag;
    } tag_entry_t;

    typedef enum logic [1:0] {
        DCACHE_OP_READ  = 2'b00,
        DCACHE_OP_WRITE = 2'b01
    } dcache_op_e;

    // Address helpers
    function automatic cache_set_t addr_to_set(input cache_addr_t addr);
        return addr[OFFSET_BITS +: INDEX_BITS];
    endfunction

    function automatic cache_tag_t addr_to_tag(input cache_addr_t addr);
        return addr[INDEX_BITS+OFFSET_BITS +: TAG_BITS];
    endfunction

    function automatic word_sel_t addr_to_word_sel(input cache_addr_t addr);
        return addr[BYTE_OFF_BITS +: WORD_SEL_BITS];
    endfunction

    // Byte address of the start of the line (offset bits zeroed).
    function automatic cache_addr_t set_tag_to_addr(
        input cache_set_t set_idx,
        input cache_tag_t tag
    );
        set_tag_to_addr = '0;
        set_tag_to_addr[OFFSET_BITS +: INDEX_BITS]          = set_idx;
        set_tag_to_addr[INDEX_BITS+OFFSET_BITS +: TAG_BITS] = tag;
    endfunction

    // Word index into the backing memory for the FIRST word of the line.
    function automatic mem_idx_t addr_to_line_base_widx(input cache_addr_t addr);
        cache_addr_t base;
        base = addr;
        base[OFFSET_BITS-1:0] = '0;
        return base[BYTE_OFF_BITS +: MEM_IDX_BITS];
    endfunction

    // PLRU (4-way tree, 3 state bits): bit0 = top, bit1 = left pair, bit2 = right
    function automatic cache_way_t plru_victim(input plru_state_t state);
        if (!state[0])
            plru_victim = state[1] ? 2'd1 : 2'd0;   // go to left pair
        else
            plru_victim = state[2] ? 2'd3 : 2'd2;   // go to right pair
    endfunction

    function automatic plru_state_t plru_touch(
        input plru_state_t state,
        input cache_way_t  way
    );
        plru_touch = state;
        unique case (way)
            2'd0: begin plru_touch[0] = 1'b1; plru_touch[1] = 1'b1; end
            2'd1: begin plru_touch[0] = 1'b1; plru_touch[1] = 1'b0; end
            2'd2: begin plru_touch[0] = 1'b0; plru_touch[2] = 1'b1; end
            2'd3: begin plru_touch[0] = 1'b0; plru_touch[2] = 1'b0; end
            default: ;
        endcase
    endfunction

    function automatic cache_way_t onehot_to_way(input way_mask_t mask);
        unique case (mask)
            4'b0001: onehot_to_way = 2'd0;
            4'b0010: onehot_to_way = 2'd1;
            4'b0100: onehot_to_way = 2'd2;
            4'b1000: onehot_to_way = 2'd3;
            default: onehot_to_way = 2'd0;
        endcase
    endfunction

    // Data helpers
    function automatic cache_word_t line_get_word(
        input cache_line_t line,
        input word_sel_t   sel
    );
        return line[int'(sel)*WORD_BITS +: WORD_BITS];
    endfunction

    // Merge a 64-bit store (with byte strobe) into the selected word of a line.
    function automatic cache_line_t line_merge_word(
        input cache_line_t old_line,
        input word_sel_t   sel,
        input cache_word_t wdata,
        input cache_strb_t strb
    );
        int base;
        line_merge_word = old_line;
        base = int'(sel) * WORD_BITS;
        for (int b = 0; b < WORD_BYTES; b++)
            if (strb[b])
                line_merge_word[base + b*8 +: 8] = wdata[b*8 +: 8];
    endfunction

endpackage
