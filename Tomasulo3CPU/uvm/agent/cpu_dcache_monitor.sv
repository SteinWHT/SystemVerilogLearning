class cpu_dcache_monitor extends uvm_monitor;
    `uvm_component_utils(cpu_dcache_monitor)

    cpu_mon_vif_t                   vif;
    uvm_analysis_port #(cpu_dcache_item#()) ap_dcache;

    function new(string name = "cpu_dcache_monitor", uvm_component parent = null);
        super.new(name, parent);
        ap_dcache = new("ap_dcache", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(cpu_mon_vif_t)::get(this, "", "mon_vif", vif))
            `uvm_fatal("NOVIF", "Set cpu_mon_vif_t on cpu_dcache_monitor via config_db")
    endfunction

    task run_phase(uvm_phase phase);
        cpu_dcache_item#() tr;
        forever begin
            @(posedge vif.clk);
            if (!vif.rst_n)
                continue;
            #1step;

            if (vif.dcache_rvalid && vif.dcache_rready) begin
                tr = cpu_dcache_item#()::type_id::create("dcache_read_req");
                tr.access = cpu_dcache_item#()::DCACHE_READ;
                tr.addr   = vif.dcache_raddr;
                tr.data   = '0;
                tr.strb   = '0;
                ap_dcache.write(tr);
            end

            if (vif.dcache_rresp_valid && vif.dcache_rresp_ready) begin
                tr = cpu_dcache_item#()::type_id::create("dcache_read_rsp");
                tr.access = cpu_dcache_item#()::DCACHE_READ;
                tr.addr   = vif.dcache_raddr;
                tr.data   = vif.dcache_rdata;
                tr.strb   = '0;
                ap_dcache.write(tr);
            end

            if (vif.dcache_wvalid && vif.dcache_wready) begin
                tr = cpu_dcache_item#()::type_id::create("dcache_write");
                tr.access = cpu_dcache_item#()::DCACHE_WRITE;
                tr.addr   = vif.dcache_sw_addr;
                tr.data   = vif.dcache_sw_data;
                tr.strb   = vif.dcache_wstrb;
                ap_dcache.write(tr);
            end
        end
    endtask
endclass
