// DPI-C bindings to the single-hart Spike functional golden model
// (uvm/tools/spike_cosim/spike_cosim.{h,cc}). Imported by cpu_pkg and used by
// the online Spike lockstep scoreboard.
package cpu_spike_dpi_pkg;

    import "DPI-C" function void    spike_cosim_init(input string isa,
                                                     input string priv,
                                                     input longint mem_base,
                                                     input longint mem_size,
                                                     input longint start_pc);
    import "DPI-C" function void    spike_cosim_final();

    import "DPI-C" function void    spike_cosim_write_word(input longint addr,
                                                           input longint data);
    import "DPI-C" function void    spike_cosim_write_u32(input longint addr,
                                                          input int data);
    import "DPI-C" function longint spike_cosim_read_word(input longint addr);

    import "DPI-C" function int     spike_cosim_step();

    import "DPI-C" function longint spike_cosim_last_pc();
    import "DPI-C" function int     spike_cosim_last_insn();
    import "DPI-C" function int     spike_cosim_last_rd();
    import "DPI-C" function longint spike_cosim_last_wdata();
    import "DPI-C" function int     spike_cosim_last_store();
    import "DPI-C" function longint spike_cosim_last_store_addr();
    import "DPI-C" function longint spike_cosim_last_store_data();
    import "DPI-C" function int     spike_cosim_last_store_size();
    import "DPI-C" function int     spike_cosim_last_load();

    import "DPI-C" function longint spike_cosim_get_gpr(input int idx);

endpackage
