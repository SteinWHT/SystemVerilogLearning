module axi_xbar_2x1 (
    input  logic clk,
    input  logic rst_n,
    axi_if.slave  s0,
    axi_if.slave  s1,
    axi_if.master m
);

    typedef enum logic [1:0] {
        X_IDLE,
        X_ADDR,
        X_WRITE,
        X_READ
    } xbar_state_e;

    xbar_state_e state;
    logic        owner;
    logic        txn_write;
    logic        rr_owner;
    logic        prefer_read;
    logic        s0_req;
    logic        s1_req;
    logic        choose_owner;
    logic        choose_write;

    assign s0_req = s0.awvalid || s0.arvalid;
    assign s1_req = s1.awvalid || s1.arvalid;

    always_comb begin
        choose_owner = 1'b0;
        if (s0_req && s1_req)
            choose_owner = rr_owner;
        else if (s1_req)
            choose_owner = 1'b1;

        if (!choose_owner) begin
            if (s0.awvalid && s0.arvalid)
                choose_write = !prefer_read;
            else
                choose_write = s0.awvalid;
        end else begin
            if (s1.awvalid && s1.arvalid)
                choose_write = !prefer_read;
            else
                choose_write = s1.awvalid;
        end
    end

    always_comb begin
        m.awid     = '0;
        m.awaddr   = '0;
        m.awlen    = '0;
        m.awsize   = '0;
        m.awburst  = '0;
        m.awlock   = 1'b0;
        m.awcache  = '0;
        m.awprot   = '0;
        m.awqos    = '0;
        m.awregion = '0;
        m.awvalid  = 1'b0;
        m.wdata    = '0;
        m.wstrb    = '0;
        m.wlast    = 1'b0;
        m.wvalid   = 1'b0;
        m.bready   = 1'b0;
        m.arid     = '0;
        m.araddr   = '0;
        m.arlen    = '0;
        m.arsize   = '0;
        m.arburst  = '0;
        m.arlock   = 1'b0;
        m.arcache  = '0;
        m.arprot   = '0;
        m.arqos    = '0;
        m.arregion = '0;
        m.arvalid  = 1'b0;
        m.rready   = 1'b0;

        s0.awready = 1'b0;
        s0.wready  = 1'b0;
        s0.bid      = m.bid;
        s0.bresp    = m.bresp;
        s0.bvalid   = 1'b0;
        s0.arready  = 1'b0;
        s0.rid      = m.rid;
        s0.rdata    = m.rdata;
        s0.rresp    = m.rresp;
        s0.rlast    = m.rlast;
        s0.rvalid   = 1'b0;

        s1.awready = 1'b0;
        s1.wready  = 1'b0;
        s1.bid      = m.bid;
        s1.bresp    = m.bresp;
        s1.bvalid   = 1'b0;
        s1.arready  = 1'b0;
        s1.rid      = m.rid;
        s1.rdata    = m.rdata;
        s1.rresp    = m.rresp;
        s1.rlast    = m.rlast;
        s1.rvalid   = 1'b0;

        if (rst_n) begin
            case (state)
                X_ADDR: begin
                    if (txn_write) begin
                        if (!owner) begin
                            m.awid     = s0.awid;
                            m.awaddr   = s0.awaddr;
                            m.awlen    = s0.awlen;
                            m.awsize   = s0.awsize;
                            m.awburst  = s0.awburst;
                            m.awlock   = s0.awlock;
                            m.awcache  = s0.awcache;
                            m.awprot   = s0.awprot;
                            m.awqos    = s0.awqos;
                            m.awregion = s0.awregion;
                            m.awvalid  = s0.awvalid;
                            s0.awready = m.awready;
                        end else begin
                            m.awid     = s1.awid;
                            m.awaddr   = s1.awaddr;
                            m.awlen    = s1.awlen;
                            m.awsize   = s1.awsize;
                            m.awburst  = s1.awburst;
                            m.awlock   = s1.awlock;
                            m.awcache  = s1.awcache;
                            m.awprot   = s1.awprot;
                            m.awqos    = s1.awqos;
                            m.awregion = s1.awregion;
                            m.awvalid  = s1.awvalid;
                            s1.awready = m.awready;
                        end
                    end else begin
                        if (!owner) begin
                            m.arid     = s0.arid;
                            m.araddr   = s0.araddr;
                            m.arlen    = s0.arlen;
                            m.arsize   = s0.arsize;
                            m.arburst  = s0.arburst;
                            m.arlock   = s0.arlock;
                            m.arcache  = s0.arcache;
                            m.arprot   = s0.arprot;
                            m.arqos    = s0.arqos;
                            m.arregion = s0.arregion;
                            m.arvalid  = s0.arvalid;
                            s0.arready = m.arready;
                        end else begin
                            m.arid     = s1.arid;
                            m.araddr   = s1.araddr;
                            m.arlen    = s1.arlen;
                            m.arsize   = s1.arsize;
                            m.arburst  = s1.arburst;
                            m.arlock   = s1.arlock;
                            m.arcache  = s1.arcache;
                            m.arprot   = s1.arprot;
                            m.arqos    = s1.arqos;
                            m.arregion = s1.arregion;
                            m.arvalid  = s1.arvalid;
                            s1.arready = m.arready;
                        end
                    end
                end

                X_WRITE: begin
                    if (!owner) begin
                        m.wdata    = s0.wdata;
                        m.wstrb    = s0.wstrb;
                        m.wlast    = s0.wlast;
                        m.wvalid   = s0.wvalid;
                        s0.wready  = m.wready;
                        s0.bvalid  = m.bvalid;
                        m.bready   = s0.bready;
                    end else begin
                        m.wdata    = s1.wdata;
                        m.wstrb    = s1.wstrb;
                        m.wlast    = s1.wlast;
                        m.wvalid   = s1.wvalid;
                        s1.wready  = m.wready;
                        s1.bvalid  = m.bvalid;
                        m.bready   = s1.bready;
                    end
                end

                X_READ: begin
                    if (!owner) begin
                        s0.rvalid = m.rvalid;
                        m.rready  = s0.rready;
                    end else begin
                        s1.rvalid = m.rvalid;
                        m.rready  = s1.rready;
                    end
                end

                default: begin
                end
            endcase
        end
    end

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= X_IDLE;
            owner       <= 1'b0;
            txn_write   <= 1'b0;
            rr_owner    <= 1'b0;
            prefer_read <= 1'b0;
        end else begin
            case (state)
                X_IDLE: begin
                    if (s0_req || s1_req) begin
                        owner     <= choose_owner;
                        txn_write <= choose_write;
                        state     <= X_ADDR;
                    end
                end

                X_ADDR: begin
                    if (txn_write && m.awvalid && m.awready)
                        state <= X_WRITE;
                    else if (!txn_write && m.arvalid && m.arready)
                        state <= X_READ;
                end

                X_WRITE: begin
                    if (m.bvalid && m.bready) begin
                        rr_owner    <= ~owner;
                        prefer_read <= 1'b1;
                        state       <= X_IDLE;
                    end
                end

                X_READ: begin
                    if (m.rvalid && m.rready && m.rlast) begin
                        rr_owner    <= ~owner;
                        prefer_read <= 1'b0;
                        state       <= X_IDLE;
                    end
                end

                default: state <= X_IDLE;
            endcase
        end
    end

endmodule
