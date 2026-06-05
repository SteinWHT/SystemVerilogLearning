class cpu_dcache_monitor extends uvm_monitor;
    `uvm_component_utils(cpu_dcache_monitor)

    cpu_mon_vif_t                   vif;
    uvm_analysis_port #(cpu_dcache_item#()) ap_dcache;
    bit [CPU_DMEM_DEPTH-1:0]        read_addr_q[$];
    bit [CPU_DMEM_DEPTH-1:0]        write_addr_q[$];
    bit [CPU_DMEM_WIDTH-1:0]        write_data_q[$];
    bit [CPU_W_BYTE_NUM-1:0]        write_strb_q[$];

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
            if (!vif.rst_n) begin
                read_addr_q.delete();
                write_addr_q.delete();
                write_data_q.delete();
                write_strb_q.delete();
                continue;
            end

            if (vif.dcache_rvalid && vif.dcache_rready) begin
                tr = cpu_dcache_item#()::type_id::create("dcache_read_req");
                tr.access     = cpu_dcache_item#()::DCACHE_READ;
                tr.event_kind = cpu_dcache_item#()::DCACHE_REQUEST;
                tr.addr       = vif.dcache_raddr;
                tr.data       = '0;
                tr.strb       = '0;
                read_addr_q.push_back(tr.addr);
                ap_dcache.write(tr);
            end

            if (vif.dcache_rresp_valid && vif.dcache_rresp_ready) begin
                tr = cpu_dcache_item#()::type_id::create("dcache_read_rsp");
                tr.access     = cpu_dcache_item#()::DCACHE_READ;
                tr.event_kind = cpu_dcache_item#()::DCACHE_RESPONSE;
                if (read_addr_q.size())
                    tr.addr = read_addr_q.pop_front();
                else begin
                    tr.addr = '0;
                    `uvm_error(get_type_name(), "Read response observed without a pending request")
                end
                tr.data       = vif.dcache_rdata;
                tr.strb       = '0;
                ap_dcache.write(tr);
            end

            if (vif.dcache_wvalid && vif.dcache_wready) begin
                tr = cpu_dcache_item#()::type_id::create("dcache_write");
                tr.access     = cpu_dcache_item#()::DCACHE_WRITE;
                tr.event_kind = cpu_dcache_item#()::DCACHE_REQUEST;
                tr.addr       = vif.dcache_sw_addr;
                tr.data       = vif.dcache_sw_data;
                tr.strb       = vif.dcache_wstrb;
                write_addr_q.push_back(tr.addr);
                write_data_q.push_back(tr.data);
                write_strb_q.push_back(tr.strb);
                ap_dcache.write(tr);
            end

            if (vif.dcache_wresp_valid && vif.dcache_wresp_ready) begin
                tr = cpu_dcache_item#()::type_id::create("dcache_write_rsp");
                tr.access     = cpu_dcache_item#()::DCACHE_WRITE;
                tr.event_kind = cpu_dcache_item#()::DCACHE_RESPONSE;
                if (write_addr_q.size()) begin
                    tr.addr = write_addr_q.pop_front();
                    tr.data = write_data_q.pop_front();
                    tr.strb = write_strb_q.pop_front();
                end else begin
                    tr.addr = '0;
                    tr.data = '0;
                    tr.strb = '0;
                    `uvm_error(get_type_name(), "Write response observed without a pending request")
                end
                ap_dcache.write(tr);
            end
        end
    endtask
endclass
