`uvm_analysis_imp_decl(_dcache_check)

class cpu_dcache_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(cpu_dcache_scoreboard)

    uvm_analysis_imp_dcache_check #(cpu_dcache_item#(), cpu_dcache_scoreboard) imp_dcache;

    cpu_drv_vif_t                  vif;
    bit [CPU_DMEM_WIDTH-1:0]       memory_model [CPU_DMEM_LINES];
    bit [CPU_DMEM_WIDTH-1:0]       expected_read_data_q[$];
    bit [CPU_DMEM_DEPTH-1:0]       expected_read_addr_q[$];
    bit [CPU_DMEM_DEPTH-1:0]       pending_write_addr_q[$];
    bit                            model_ready;
    int unsigned                   reads_checked;
    int unsigned                   writes_checked;
    int unsigned                   mismatches;

    function new(string name = "cpu_dcache_scoreboard", uvm_component parent = null);
        super.new(name, parent);
        imp_dcache = new("imp_dcache", this);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(cpu_drv_vif_t)::get(this, "", "vif", vif))
            `uvm_fatal("NOVIF", "Set cpu_drv_vif_t on cpu_dcache_scoreboard via config_db")
    endfunction

    task run_phase(uvm_phase phase);
        wait (vif.preload_complete === 1'b1);
        for (int unsigned i = 0; i < CPU_DMEM_LINES; i++)
            memory_model[i] = vif.read_dmem_line(i * (CPU_DMEM_WIDTH / 8));
        model_ready = 1'b1;
    endtask

    virtual function void write_dcache_check(cpu_dcache_item#() tr);
        int unsigned line_idx;
        bit [CPU_DMEM_WIDTH-1:0] expected_data;
        bit [CPU_DMEM_DEPTH-1:0] expected_addr;

        if (!model_ready) begin
            `uvm_error(get_type_name(), $sformatf(
                "D-cache traffic arrived before memory model initialization: %0s",
                tr.convert2string()))
            mismatches++;
            return;
        end

        line_idx = tr.addr[CPU_DMEM_DEPTH-1:3];
        if (line_idx >= CPU_DMEM_LINES) begin
            `uvm_error(get_type_name(), $sformatf(
                "D-cache address outside scoreboard memory: %0s", tr.convert2string()))
            mismatches++;
            return;
        end

        if (tr.event_kind == cpu_dcache_item#()::DCACHE_REQUEST) begin
            if (tr.access == cpu_dcache_item#()::DCACHE_READ) begin
                expected_read_addr_q.push_back(tr.addr);
                expected_read_data_q.push_back(memory_model[line_idx]);
            end else begin
                for (int unsigned byte_idx = 0; byte_idx < CPU_W_BYTE_NUM; byte_idx++) begin
                    if (tr.strb[byte_idx])
                        memory_model[line_idx][byte_idx*8 +: 8] =
                            tr.data[byte_idx*8 +: 8];
                end
                pending_write_addr_q.push_back(tr.addr);
                writes_checked++;
            end
            return;
        end

        if (tr.access == cpu_dcache_item#()::DCACHE_READ) begin
            if (!expected_read_data_q.size()) begin
                `uvm_error(get_type_name(), $sformatf(
                    "Unexpected D-cache read response: %0s", tr.convert2string()))
                mismatches++;
                return;
            end
            expected_addr = expected_read_addr_q.pop_front();
            expected_data = expected_read_data_q.pop_front();
            if (tr.addr !== expected_addr || tr.data !== expected_data) begin
                `uvm_error(get_type_name(), $sformatf(
                    "D-cache read mismatch addr exp=0x%0h act=0x%0h data exp=0x%016h act=0x%016h",
                    expected_addr, tr.addr, expected_data, tr.data))
                mismatches++;
            end
            reads_checked++;
        end else begin
            if (!pending_write_addr_q.size()) begin
                `uvm_error(get_type_name(), $sformatf(
                    "Unexpected D-cache write response: %0s", tr.convert2string()))
                mismatches++;
            end else begin
                expected_addr = pending_write_addr_q.pop_front();
                if (tr.addr !== expected_addr) begin
                    `uvm_error(get_type_name(), $sformatf(
                        "D-cache write response address mismatch exp=0x%0h act=0x%0h",
                        expected_addr, tr.addr))
                    mismatches++;
                end
            end
        end
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        if (expected_read_data_q.size() || pending_write_addr_q.size()) begin
            `uvm_error(get_type_name(), $sformatf(
                "D-cache transactions left pending: reads=%0d writes=%0d",
                expected_read_data_q.size(), pending_write_addr_q.size()))
            mismatches++;
        end

        if (mismatches == 0)
            `uvm_info(get_type_name(), $sformatf(
                "D-cache scoreboard passed: reads=%0d writes=%0d",
                reads_checked, writes_checked), UVM_LOW)
        else
            `uvm_error(get_type_name(), $sformatf(
                "D-cache scoreboard failed: mismatches=%0d reads=%0d writes=%0d",
                mismatches, reads_checked, writes_checked))
    endfunction
endclass
