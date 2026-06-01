interface cpu_if #(
    parameter int unsigned INSTR_WIDTH  = 32,
    parameter int unsigned IMEM_DEPTH   = 64,
    parameter int unsigned IMEM_WIDTH   = 32,
    parameter int unsigned DMEM_WIDTH   = 64,
    parameter int unsigned DMEM_DEPTH   = 32,
    parameter int unsigned W_BYTE_NUM   = DMEM_WIDTH / 8,
    parameter int unsigned IMEM_WORDS   = 1024,
    parameter int unsigned DMEM_LINES   = 256
)(
    input logic clk,
    input logic rst_n
);

    // DUT-facing buses (driven/sampled by tb memory models)
    logic                   imem_valid;
    logic [IMEM_WIDTH-1:0]  imem_data;
    logic                   imem_read_rdy;
    logic [IMEM_DEPTH-1:0]  imem_addr;

    logic                   dcache_rvalid;
    logic                   dcache_rresp_valid;
    logic [DMEM_WIDTH-1:0]  dcache_rdata;
    logic [DMEM_DEPTH-1:0]  dcache_raddr;
    logic                   dcache_rready;
    logic                   dcache_rresp_ready;

    logic                   dcache_wvalid;
    logic                   dcache_wresp_valid;
    logic                   dcache_write;
    logic [DMEM_WIDTH-1:0]  dcache_sw_data;
    logic [W_BYTE_NUM-1:0]  dcache_wstrb;
    logic [DMEM_DEPTH-1:0]  dcache_sw_addr;
    logic                   dcache_wready;
    logic                   dcache_wresp_ready;

    // Memory images (program/data preload from driver/sequences — not PRF force)
    logic [INSTR_WIDTH-1:0] imem_array [IMEM_WORDS];
    logic [DMEM_WIDTH-1:0]  dmem_array [DMEM_LINES];

    task automatic load_instr(
        input logic [IMEM_DEPTH-1:0] byte_addr,
        input logic [INSTR_WIDTH-1:0] instr
    );
        imem_array[byte_addr[IMEM_DEPTH-1:2]] = instr;
    endtask

    task automatic write_dmem_line(
        input int unsigned            line_idx,
        input logic [DMEM_WIDTH-1:0]  data
    );
        dmem_array[line_idx] = data;
    endtask

    function automatic logic [INSTR_WIDTH-1:0] nop();
        // ADDI x0, x0, 0
        return 32'h0000_0013;
    endfunction

    task automatic fill_nops(
        input logic [IMEM_DEPTH-1:0] byte_addr,
        input int unsigned count
    );
        for (int unsigned i = 0; i < count; i++) begin
            load_instr(byte_addr + (i << 2), nop());
        end
    endtask

    modport dut_mp (
        input  clk,
        input  rst_n,
        input  imem_valid,
        input  imem_data,
        output imem_read_rdy,
        output imem_addr,
        input  dcache_rvalid,
        input  dcache_rresp_valid,
        input  dcache_rdata,
        output dcache_raddr,
        output dcache_rready,
        output dcache_rresp_ready,
        input  dcache_wvalid,
        input  dcache_wresp_valid,
        input  dcache_write,
        input  dcache_sw_data,
        input  dcache_wstrb,
        input  dcache_sw_addr,
        output dcache_wready,
        output dcache_wresp_ready
    );

    modport drv_mp (
        input  clk,
        input  rst_n,
        import load_instr,
        import write_dmem_line,
        import fill_nops,
        import nop
    );

endinterface
