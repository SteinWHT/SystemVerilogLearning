interface cpu_if #(
    parameter int unsigned INSTR_WIDTH  = 32,
    parameter int unsigned PC_WIDTH   = 64,
    parameter int unsigned IMEM_WIDTH   = 32,
    parameter int unsigned DMEM_WIDTH   = 64,
    parameter int unsigned DMEM_ADDR_WIDTH   = 32,
    parameter int unsigned W_BYTE_NUM   = DMEM_WIDTH / 8,
    parameter int unsigned IMEM_WORDS   = 1024,
    parameter int unsigned DMEM_LINES   = 256,
    parameter int unsigned MEM_IDX_BITS = 16,
    parameter int unsigned AXI_IMEM_BASE_WORD = 32768
)(
    input logic clk,
    input logic rst_n,
    input logic use_axi_memory
);

    // DUT-facing buses (driven/sampled by tb memory models)
    logic                   imem_resp_valid;
    logic                   imem_resp_ready;
    logic [IMEM_WIDTH-1:0]  imem_resp_data;
    logic                   imem_req_valid;
    logic                   imem_req_ready;
    logic [PC_WIDTH-1:0]  imem_addr;

    logic                   dcache_rready;
    logic                   dcache_rresp_valid;
    logic [DMEM_WIDTH-1:0]  dcache_rdata;
    logic [DMEM_ADDR_WIDTH-1:0]  dcache_raddr;
    logic                   dcache_rvalid;
    logic                   dcache_rresp_ready;

    logic                   dcache_wready;
    logic                   dcache_wresp_valid;
    logic                   dcache_write;
    logic [DMEM_WIDTH-1:0]  dcache_sw_data;
    logic [W_BYTE_NUM-1:0]  dcache_wstrb;
    logic [DMEM_ADDR_WIDTH-1:0]  dcache_sw_addr;
    logic                   dcache_wvalid;
    logic                   dcache_wresp_ready;

    logic                       dcache_mem_init_en;
    logic [MEM_IDX_BITS-1:0]    dcache_mem_init_idx;
    logic [DMEM_WIDTH-1:0]      dcache_mem_init_data;
    logic                       axi_mem_init_en;
    logic [DMEM_ADDR_WIDTH-1:0]      axi_mem_init_word_idx;
    logic [DMEM_WIDTH-1:0]      axi_mem_init_data;
    logic [31:0]                dcache_hits;
    logic [31:0]                dcache_misses;
    logic                       memory_error;
    logic                       preload_complete;

    // Memory images (program/data preload from driver/sequences — not PRF force)
    logic [INSTR_WIDTH-1:0] imem_array [IMEM_WORDS];
    logic [DMEM_WIDTH-1:0]  dmem_array [DMEM_LINES];

    localparam int unsigned AXI_INSTRS_PER_WORD = DMEM_WIDTH / INSTR_WIDTH;

    initial begin
        if (INSTR_WIDTH == 0 || DMEM_WIDTH < INSTR_WIDTH ||
            (DMEM_WIDTH % INSTR_WIDTH) != 0)
            $fatal(1, "cpu_if: AXI word must contain a whole number of instructions");
        // AXI_IMEM_BASE_WORD == 0 selects a unified (von Neumann) memory: the I and
        // D views share one address space, so overlap is expected (and is exactly
        // what FENCE.I coherence must handle). A non-zero base keeps the legacy
        // split instruction window, where the D image must stay below it.
        if (use_axi_memory && AXI_IMEM_BASE_WORD != 0 && DMEM_LINES > AXI_IMEM_BASE_WORD)
            $fatal(1, "cpu_if: D-memory image overlaps AXI instruction window");

        dcache_mem_init_en   = 1'b0;
        dcache_mem_init_idx  = '0;
        dcache_mem_init_data = '0;
        axi_mem_init_en      = 1'b0;
        axi_mem_init_word_idx = '0;
        axi_mem_init_data    = '0;
        preload_complete     = 1'b0;
        for (int unsigned i = 0; i < IMEM_WORDS; i++)
            imem_array[i] = nop();
        for (int unsigned i = 0; i < DMEM_LINES; i++)
            dmem_array[i] = '0;
    end

    task automatic write_axi_word(
        input int unsigned           word_idx,
        input logic [DMEM_WIDTH-1:0] data
    );
        @(negedge clk);
        axi_mem_init_en       = 1'b1;
        axi_mem_init_word_idx = DMEM_ADDR_WIDTH'(word_idx);
        axi_mem_init_data     = data;
        @(negedge clk);
        axi_mem_init_en       = 1'b0;
    endtask

    task automatic load_instr(
        input logic [PC_WIDTH-1:0] byte_addr,
        input logic [INSTR_WIDTH-1:0] instr
    );
        int unsigned instr_idx;
        int unsigned first_instr_idx;
        int unsigned axi_word_idx;
        logic [DMEM_WIDTH-1:0] packed_word;

        instr_idx = int'(byte_addr / (INSTR_WIDTH / 8));
        if (instr_idx >= IMEM_WORDS)
            $fatal(1, "cpu_if.load_instr: byte address 0x%0h is outside IMEM", byte_addr);

        imem_array[instr_idx] = instr;
        if (use_axi_memory) begin
            axi_word_idx = AXI_IMEM_BASE_WORD + (instr_idx / AXI_INSTRS_PER_WORD);
            first_instr_idx = (instr_idx / AXI_INSTRS_PER_WORD) * AXI_INSTRS_PER_WORD;
            packed_word = '0;
            for (int unsigned lane = 0; lane < AXI_INSTRS_PER_WORD; lane++) begin
                if ((first_instr_idx + lane) < IMEM_WORDS)
                    packed_word[lane*INSTR_WIDTH +: INSTR_WIDTH] =
                        imem_array[first_instr_idx + lane];
            end
            write_axi_word(axi_word_idx, packed_word);
        end
    endtask

    task automatic write_dmem_line(
        input int unsigned            line_idx,
        input logic [DMEM_WIDTH-1:0]  data
    );
        dmem_array[line_idx] = data;
        if (use_axi_memory) begin
            write_axi_word(line_idx, data);
        end else begin
            @(negedge clk);
            dcache_mem_init_en   = 1'b1;
            dcache_mem_init_idx  = MEM_IDX_BITS'(line_idx);
            dcache_mem_init_data = data;
            @(negedge clk);
            dcache_mem_init_en = 1'b0;
        end
    endtask

    function automatic logic [INSTR_WIDTH-1:0] nop();
        // ADDI x0, x0, 0
        return 32'h0000_0013;
    endfunction

    task automatic fill_nops(
        input logic [PC_WIDTH-1:0] byte_addr,
        input int unsigned count
    );
        for (int unsigned i = 0; i < count; i++) begin
            load_instr(byte_addr + (i << 2), nop());
        end
    endtask

    task automatic clear_memories();
        preload_complete = 1'b0;
        dcache_mem_init_en = 1'b0;
        axi_mem_init_en = 1'b0;
        for (int unsigned i = 0; i < IMEM_WORDS; i++)
            imem_array[i] = nop();
        for (int unsigned i = 0; i < DMEM_LINES; i++)
            dmem_array[i] = '0;
    endtask

    task automatic load_imem_file(input string path);
        logic [DMEM_WIDTH-1:0] packed_word;

        $readmemh(path, imem_array);
        if (use_axi_memory) begin
            for (int unsigned i = 0; i < IMEM_WORDS; i += AXI_INSTRS_PER_WORD) begin
                packed_word = '0;
                for (int unsigned lane = 0; lane < AXI_INSTRS_PER_WORD; lane++) begin
                    if ((i + lane) < IMEM_WORDS)
                        packed_word[lane*INSTR_WIDTH +: INSTR_WIDTH] =
                            imem_array[i + lane];
                end
                write_axi_word(
                    AXI_IMEM_BASE_WORD + (i / AXI_INSTRS_PER_WORD),
                    packed_word
                );
            end
        end
    endtask

    task automatic load_dmem_file(input string path);
        $readmemh(path, dmem_array);
        for (int unsigned i = 0; i < DMEM_LINES; i++) begin
            if (use_axi_memory) begin
                write_axi_word(i, dmem_array[i]);
            end else begin
                @(negedge clk);
                dcache_mem_init_en   = 1'b1;
                dcache_mem_init_idx  = MEM_IDX_BITS'(i);
                dcache_mem_init_data = dmem_array[i];
                @(negedge clk);
            end
        end
        dcache_mem_init_en   = 1'b0;
        dcache_mem_init_idx  = '0;
        dcache_mem_init_data = '0;
        axi_mem_init_en       = 1'b0;
        axi_mem_init_word_idx = '0;
        axi_mem_init_data     = '0;
    endtask

    task automatic finish_preload();
        preload_complete = 1'b1;
    endtask

    function automatic logic [DMEM_WIDTH-1:0] read_dmem_line(
        input logic [DMEM_ADDR_WIDTH-1:0] byte_addr
    );
        return dmem_array[byte_addr[DMEM_ADDR_WIDTH-1:3]];
    endfunction

    function automatic logic [31:0] read_dmem_word32(
        input logic [DMEM_ADDR_WIDTH-1:0] byte_addr
    );
        logic [DMEM_WIDTH-1:0] line;
        line = read_dmem_line(byte_addr);
        case (byte_addr[2])
            1'b0: return line[31:0];
            1'b1: return line[63:32];
        endcase
    endfunction

    modport dut_mp (
        input  clk,
        input  rst_n,
        input  imem_resp_valid,
        input  imem_resp_data,
        output imem_resp_ready,
        output imem_req_valid,
        input  imem_req_ready,
        output imem_addr,
        input  dcache_rready,
        input  dcache_rresp_valid,
        input  dcache_rdata,
        output dcache_raddr,
        output dcache_rvalid,
        output dcache_rresp_ready,
        input  dcache_wready,
        input  dcache_wresp_valid,
        input  dcache_write,
        input  dcache_sw_data,
        input  dcache_wstrb,
        input  dcache_sw_addr,
        output dcache_wvalid,
        output dcache_wresp_ready
    );

    modport drv_mp (
        input  clk,
        input  rst_n,
        input  preload_complete,
        input  dcache_wresp_valid,
        input  dcache_wresp_ready,
        input  dcache_hits,
        input  dcache_misses,
        input  memory_error,
        import load_instr,
        import write_dmem_line,
        import fill_nops,
        import clear_memories,
        import load_imem_file,
        import load_dmem_file,
        import finish_preload,
        import read_dmem_line,
        import read_dmem_word32,
        import nop
    );

    modport mon_mp (
        input  clk,
        input  rst_n,
        input  dcache_rready,
        input  dcache_rresp_valid,
        input  dcache_rdata,
        input  dcache_raddr,
        input  dcache_rvalid,
        input  dcache_rresp_ready,
        input  dcache_wready,
        input  dcache_wresp_valid,
        input  dcache_write,
        input  dcache_sw_data,
        input  dcache_wstrb,
        input  dcache_sw_addr,
        input  dcache_wvalid,
        input  dcache_wresp_ready
    );

endinterface
