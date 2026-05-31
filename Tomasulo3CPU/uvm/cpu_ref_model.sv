// Optional reference model hook — replace scoreboard algorithmic checks when complexity grows.
// Industry pattern: RM predicts commit stream; scoreboard compares monitor vs RM.
`uvm_analysis_imp_decl(_rm_instr)

virtual class cpu_ref_model extends uvm_component;
    // No `uvm_component_utils — abstract; instantiate cpu_add_ref_model (or derivatives) only.

    uvm_analysis_imp_rm_instr #(cpu_base_item, cpu_ref_model) imp_instr;
    uvm_analysis_port #(cpu_commit_tr)                        ap_predict;

    function new(string name = "cpu_ref_model", uvm_component parent = null);
        super.new(name, parent);
        imp_instr  = new("imp_instr", this);
        ap_predict = new("ap_predict", this);
    endfunction

    virtual function void write_rm_instr(cpu_base_item t);
        cpu_commit_tr pred;
        if (!build_prediction(t, pred))
            return;
        ap_predict.write(pred);
    endfunction

    // Return 0 when this RM does not model the instruction yet.
    protected virtual function bit build_prediction(
        input  cpu_base_item t,
        output cpu_commit_tr pred
    );
        return 1'b0;
    endfunction

endclass

// Lightweight ADD/ADDW predictor for early bring-up (optional wiring in cpu_env).
class cpu_add_ref_model extends cpu_ref_model;
    `uvm_component_utils(cpu_add_ref_model)

    function new(string name = "cpu_add_ref_model", uvm_component parent = null);
        super.new(name, parent);
    endfunction

    protected virtual function bit build_prediction(
        input  cpu_base_item t,
        output cpu_commit_tr pred
    );
        cpu_add_item add_tr;
        if (!$cast(add_tr, t))
            return 1'b0;
        if (!add_tr.expects_reg_write())
            return 1'b0;

        pred = cpu_commit_tr::type_id::create("pred");
        pred.valid    = 1'b1;
        pred.rw       = 1'b1;
        pred.rd_addr  = add_tr.rd;
        pred.pc       = add_tr.pc[CPU_IMEM_DEPTH-1:0];
        pred.cdb_data = add_tr.expected_result;
        return 1'b1;
    endfunction

endclass
