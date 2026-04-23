class fifo_env extends uvm_env;
    `uvm_component_utils(fifo_env)

    fifo_wr_agent     wr_agt;
    fifo_rd_agent     rd_agt;
    fifo_scoreboard   sb;

    function new(string name, uvm_component parent);
        super.new(name, parent);
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        wr_agt = fifo_wr_agent::type_id::create("wr_agt", this);
        rd_agt = fifo_rd_agent::type_id::create("rd_agt", this);
        sb     = fifo_scoreboard::type_id::create("sb", this);
    endfunction

    function void connect_phase(uvm_phase phase);
        super.connect_phase(phase);
        wr_agt.mon.ap.connect(sb.imp_wr);
        rd_agt.mon.ap.connect(sb.imp_rd);
    endfunction
endclass
