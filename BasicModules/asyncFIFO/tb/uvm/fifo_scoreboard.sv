`uvm_analysis_imp_decl(_wr)
`uvm_analysis_imp_decl(_rd)

class fifo_scoreboard extends uvm_scoreboard;
    `uvm_component_utils(fifo_scoreboard)

    uvm_analysis_imp_wr #(fifo_wr_item, fifo_scoreboard) imp_wr;
    uvm_analysis_imp_rd #(fifo_rd_obs_item, fifo_scoreboard) imp_rd;

    bit [7:0] exp_q[$];
    int unsigned mismatches;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        imp_wr = new("imp_wr", this);
        imp_rd = new("imp_rd", this);
        mismatches = 0;
    endfunction

    virtual function void write_wr(fifo_wr_item t);
        exp_q.push_back(t.data);
        `uvm_info("SB", $sformatf("Expect push data=%0h depth=%0d", t.data, exp_q.size()), UVM_MEDIUM)
    endfunction

    virtual function void write_rd(fifo_rd_obs_item t);
        bit [7:0] exp;
        if (exp_q.size() == 0) begin
            `uvm_error("SB", $sformatf("Read beat data=%0h but scoreboard empty", t.data))
            mismatches++;
        end else begin
            exp = exp_q.pop_front();
            if (t.data !== exp) begin
                `uvm_error("SB", $sformatf("Mismatch exp=%0h got=%0h", exp, t.data))
                mismatches++;
            end else begin
                `uvm_info("SB", $sformatf("Match data=%0h left=%0d", t.data, exp_q.size()), UVM_MEDIUM)
            end
        end
    endfunction

    function void report_phase(uvm_phase phase);
        super.report_phase(phase);
        if (exp_q.size() != 0 || mismatches != 0) begin
            `uvm_error("SB", $sformatf("Summary: mismatches=%0d leftover_expects=%0d", mismatches,
                                      exp_q.size()))
        end else begin
            `uvm_info("SB", "All reads matched writes.", UVM_LOW)
        end
    endfunction
endclass
