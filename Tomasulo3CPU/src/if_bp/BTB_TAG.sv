`timescale 1ns/1ps

module BTB_TAG
    import riscv_btb_pkg::*;
#(
    parameter int unsigned XLEN         = 64,
    parameter int unsigned FETCH_BYTES  = 16,
    parameter int unsigned NUM_SETS     = 128,
    parameter int unsigned NUM_WAYS     = 4,

    localparam int unsigned INST_ALIGN_BYTES = 4,
    localparam int unsigned ALIGN_BITS       = $clog2(INST_ALIGN_BYTES),
    localparam int unsigned OFFSET_BITS      = $clog2(FETCH_BYTES),
    localparam int unsigned SET_BITS         = (NUM_SETS > 1) ? $clog2(NUM_SETS) : 1,
    localparam int unsigned TAG_BITS         = XLEN - OFFSET_BITS - $clog2(NUM_SETS),
    localparam int unsigned WAY_BITS         = (NUM_WAYS > 1) ? $clog2(NUM_WAYS) : 1,
    localparam int unsigned BR_OFF_BITS      =
        (FETCH_BYTES > INST_ALIGN_BYTES) ?
        $clog2(FETCH_BYTES / INST_ALIGN_BYTES) : 1
)(
    input  logic                    clk,
    input  logic                    rst_n,

    input  logic                    lookup_valid_i,
    input  logic [XLEN-1:0]         lookup_pc_i,

    output logic                    resp_valid_o,
    output logic                    resp_hit_o,
    output logic [XLEN-1:0]         resp_pc_o,
    output logic [XLEN-1:0]         resp_branch_pc_o,
    output logic [XLEN-1:0]         resp_target_o,
    output btb_br_type_e            resp_br_type_o,

    input  logic                    update_valid_i,
    input  logic [XLEN-1:0]         update_pc_i,
    input  logic [XLEN-1:0]         update_target_i,
    input  btb_br_type_e            update_br_type_i,
    input  logic                    update_taken_i,
    input  logic                    update_allocate_i,

    // Clears both the response pipeline and all learned entries.
    input  logic                    flush_i
);

    typedef logic [TAG_BITS-1:0]    tag_t;
    typedef logic [SET_BITS-1:0]    set_t;
    typedef logic [WAY_BITS-1:0]    way_t;
    typedef logic [BR_OFF_BITS-1:0] br_off_t;

    logic         valid_mem         [NUM_SETS][NUM_WAYS];
    tag_t         tag_mem           [NUM_SETS][NUM_WAYS];
    br_off_t      branch_offset_mem [NUM_SETS][NUM_WAYS];
    logic [XLEN-1:0] target_mem     [NUM_SETS][NUM_WAYS];
    btb_br_type_e br_type_mem       [NUM_SETS][NUM_WAYS];
    way_t         repl_ptr          [NUM_SETS];

    function automatic set_t get_set(input logic [XLEN-1:0] pc);
        if (NUM_SETS == 1)
            get_set = '0;
        else
            get_set = set_t'(pc >> OFFSET_BITS);
    endfunction

    function automatic tag_t get_tag(input logic [XLEN-1:0] pc);
        get_tag = tag_t'(pc >> (OFFSET_BITS + $clog2(NUM_SETS)));
    endfunction

    function automatic br_off_t get_branch_offset(input logic [XLEN-1:0] pc);
        if (FETCH_BYTES == INST_ALIGN_BYTES)
            get_branch_offset = '0;
        else
            get_branch_offset = br_off_t'(pc >> ALIGN_BITS);
    endfunction

    function automatic logic [XLEN-1:0] get_branch_pc(
        input logic [XLEN-1:0] block_pc,
        input br_off_t         branch_offset
    );
        logic [XLEN-1:0] offset;
        begin
            offset = XLEN'(branch_offset) << ALIGN_BITS;
            get_branch_pc = (block_pc >> OFFSET_BITS << OFFSET_BITS) | offset;
        end
    endfunction

    function automatic logic [XLEN-1:0] normalize_target(
        input logic [XLEN-1:0] target,
        input btb_br_type_e    br_type
    );
        logic [XLEN-1:0] result;
        begin
            result = target;
            if (br_type == BTB_IND ||
                br_type == BTB_ICALL ||
                br_type == BTB_RET) begin
                result[0] = 1'b0;
            end
            normalize_target = result;
        end
    endfunction

    set_t               lookup_set;
    tag_t               lookup_tag;
    logic [NUM_WAYS-1:0] lookup_way_hit;
    logic               lookup_hit;
    way_t               lookup_hit_way;

    assign lookup_set = get_set(lookup_pc_i);
    assign lookup_tag = get_tag(lookup_pc_i);

    always_comb begin
        lookup_way_hit = '0;
        for (int w = 0; w < NUM_WAYS; w++) begin
            lookup_way_hit[w] =
                valid_mem[lookup_set][w] &&
                (tag_mem[lookup_set][w] == lookup_tag);
        end
    end

    always_comb begin
        lookup_hit     = 1'b0;
        lookup_hit_way = '0;
        for (int w = NUM_WAYS - 1; w >= 0; w--) begin
            if (lookup_way_hit[w]) begin
                lookup_hit     = 1'b1;
                lookup_hit_way = way_t'(w);
            end
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush_i) begin
            resp_valid_o     <= 1'b0;
            resp_hit_o       <= 1'b0;
            resp_pc_o        <= '0;
            resp_branch_pc_o <= '0;
            resp_target_o    <= '0;
            resp_br_type_o   <= BTB_NONE;
        end else begin
            resp_valid_o <= lookup_valid_i;
            resp_hit_o   <= lookup_valid_i && lookup_hit;
            resp_pc_o    <= lookup_pc_i;

            if (lookup_valid_i && lookup_hit) begin
                resp_branch_pc_o <= get_branch_pc(
                    lookup_pc_i,
                    branch_offset_mem[lookup_set][lookup_hit_way]
                );
                resp_target_o  <= target_mem[lookup_set][lookup_hit_way];
                resp_br_type_o <= br_type_mem[lookup_set][lookup_hit_way];
            end else begin
                resp_branch_pc_o <= '0;
                resp_target_o    <= '0;
                resp_br_type_o   <= BTB_NONE;
            end
        end
    end

    set_t                update_set;
    tag_t                update_tag;
    br_off_t             update_branch_offset;
    logic [NUM_WAYS-1:0] update_way_hit;
    logic                update_hit;
    way_t                update_hit_way;
    way_t                update_alloc_way;
    logic                should_write_entry;

    assign update_set           = get_set(update_pc_i);
    assign update_tag           = get_tag(update_pc_i);
    assign update_branch_offset = get_branch_offset(update_pc_i);

    always_comb begin
        update_way_hit = '0;
        for (int w = 0; w < NUM_WAYS; w++) begin
            update_way_hit[w] =
                valid_mem[update_set][w] &&
                (tag_mem[update_set][w] == update_tag);
        end
    end

    always_comb begin
        update_hit     = 1'b0;
        update_hit_way = '0;
        for (int w = NUM_WAYS - 1; w >= 0; w--) begin
            if (update_way_hit[w]) begin
                update_hit     = 1'b1;
                update_hit_way = way_t'(w);
            end
        end
    end

    always_comb begin
        update_alloc_way = repl_ptr[update_set];
        for (int w = NUM_WAYS - 1; w >= 0; w--) begin
            if (!valid_mem[update_set][w])
                update_alloc_way = way_t'(w);
        end
    end

    assign should_write_entry =
        update_valid_i &&
        (update_br_type_i != BTB_NONE) &&
        (update_taken_i || update_allocate_i);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n || flush_i) begin
            for (int s = 0; s < NUM_SETS; s++) begin
                repl_ptr[s] <= '0;
                for (int w = 0; w < NUM_WAYS; w++) begin
                    valid_mem[s][w]         <= 1'b0;
                    tag_mem[s][w]           <= '0;
                    branch_offset_mem[s][w] <= '0;
                    target_mem[s][w]        <= '0;
                    br_type_mem[s][w]       <= BTB_NONE;
                end
            end
        end else if (should_write_entry) begin
            if (update_hit) begin
                valid_mem[update_set][update_hit_way]         <= 1'b1;
                tag_mem[update_set][update_hit_way]           <= update_tag;
                branch_offset_mem[update_set][update_hit_way] <= update_branch_offset;
                target_mem[update_set][update_hit_way]        <=
                    normalize_target(update_target_i, update_br_type_i);
                br_type_mem[update_set][update_hit_way]       <= update_br_type_i;
            end else begin
                valid_mem[update_set][update_alloc_way]         <= 1'b1;
                tag_mem[update_set][update_alloc_way]           <= update_tag;
                branch_offset_mem[update_set][update_alloc_way] <= update_branch_offset;
                target_mem[update_set][update_alloc_way]        <=
                    normalize_target(update_target_i, update_br_type_i);
                br_type_mem[update_set][update_alloc_way]       <= update_br_type_i;

                if (update_alloc_way == way_t'(NUM_WAYS - 1))
                    repl_ptr[update_set] <= '0;
                else
                    repl_ptr[update_set] <= update_alloc_way + way_t'(1);
            end
        end
    end

    // synthesis translate_off
    initial begin
        assert (XLEN > OFFSET_BITS + $clog2(NUM_SETS))
            else $fatal(1, "BTBTAG: address width is too small");
        assert (FETCH_BYTES >= INST_ALIGN_BYTES &&
                (FETCH_BYTES & (FETCH_BYTES - 1)) == 0)
            else $fatal(1, "BTBTAG: FETCH_BYTES must be a power of two >= 4");
        assert (NUM_SETS > 0 && (NUM_SETS & (NUM_SETS - 1)) == 0)
            else $fatal(1, "BTBTAG: NUM_SETS must be a power of two");
        assert (NUM_WAYS > 0 && (NUM_WAYS & (NUM_WAYS - 1)) == 0)
            else $fatal(1, "BTBTAG: NUM_WAYS must be a power of two");
    end
    // synthesis translate_on

endmodule
