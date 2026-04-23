class fifo_smoke_test extends uvm_test;
    `uvm_component_utils(fifo_smoke_test)

    fifo_env       env;
    virtual fifo_if vif;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db#(virtual fifo_if)::get(this, "", "vif", vif)) begin
            `uvm_fatal("NOVIF", "tb_top must set virtual fifo_if for uvm_test_top")
        end
        uvm_config_db#(virtual fifo_if)::set(this, "env.*", "vif", vif);
        env = fifo_env::type_id::create("env", this);
    endfunction

    task run_phase(uvm_phase phase);
        fifo_wr_seq wr_seq;
        fifo_rd_seq rd_seq;
        phase.raise_objection(this);
        wr_seq = fifo_wr_seq::type_id::create("wr_seq");
        rd_seq = fifo_rd_seq::type_id::create("rd_seq");
        fork
            wr_seq.start(env.wr_agt.sqr);
            begin
                // Let a few words accumulate before reads start (interesting for CDC).
                repeat (8) @(posedge vif.wclk);
                rd_seq.start(env.rd_agt.sqr);
            end
        join
        // Let monitors / scoreboard drain.
        repeat (40) @(posedge vif.rclk);
        phase.drop_objection(this);
    endtask
endclass
