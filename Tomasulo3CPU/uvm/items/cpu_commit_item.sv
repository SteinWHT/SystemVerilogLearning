class cpu_commit_item #(
    int unsigned ROB_INDEX_WIDTH         = 4,
    int unsigned DMEM_DEPTH              = 32,
    int unsigned IMEM_DEPTH              = 64,
    int unsigned REG_FILE_DATA_WIDTH     = 64,
    int unsigned ARCH_REG_WIDTH          = 5,
    int unsigned PHY_REGISTER_FILE_WIDTH = 7,
    int unsigned W_BYTE_NUM              = 8,
    int unsigned TRAP_CAUSE_WIDTH        = 4,
    int unsigned CSR_ADDR_WIDTH          = 12,
    int unsigned CSR_CMD_WIDTH           = 3
) extends uvm_sequence_item;

    // Commit transaction identity
    bit                                 valid;
    bit [ROB_INDEX_WIDTH-1:0]           rob_tag;
    time                                commit_time;

    // rob_entry_t payload (see Tomasulo3CPU/src/ROB.sv)
    bit [PHY_REGISTER_FILE_WIDTH-1:0] curr_phy;
    bit [PHY_REGISTER_FILE_WIDTH-1:0] prev_phy;
    bit [ARCH_REG_WIDTH-1:0]          rd_addr;
    bit                               rw;
    bit                               mw;
    bit                               compl;
    bit [DMEM_DEPTH-1:0]              sw_addr;
    bit [W_BYTE_NUM-1:0]              sw_strb;
    bit [IMEM_DEPTH-1:0]              pc;
    bit [TRAP_CAUSE_WIDTH-1:0]        trap_cause;
    bit                               mret_occur;
    bit                               is_csr;
    bit [CSR_ADDR_WIDTH-1:0]          csr_addr;
    bit [CSR_CMD_WIDTH-1:0]           csr_cmd;
    bit [ARCH_REG_WIDTH-1:0]          rs1_arch;
    bit [REG_FILE_DATA_WIDTH-1:0]     cdb_data;

    `uvm_object_param_utils_begin(cpu_commit_item #(
        ROB_INDEX_WIDTH,
        DMEM_DEPTH,
        IMEM_DEPTH,
        REG_FILE_DATA_WIDTH,
        ARCH_REG_WIDTH,
        PHY_REGISTER_FILE_WIDTH,
        W_BYTE_NUM,
        TRAP_CAUSE_WIDTH,
        CSR_ADDR_WIDTH,
        CSR_CMD_WIDTH
    ))
        `uvm_field_int(valid,                UVM_ALL_ON)
        `uvm_field_int(rob_tag,              UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(commit_time,          UVM_ALL_ON | UVM_TIME)
        `uvm_field_int(curr_phy,             UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(prev_phy,             UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(rd_addr,              UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(rw,                   UVM_ALL_ON)
        `uvm_field_int(mw,                   UVM_ALL_ON)
        `uvm_field_int(compl,                UVM_ALL_ON)
        `uvm_field_int(sw_addr,              UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(sw_strb,              UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(pc,                   UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(trap_cause,           UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(mret_occur,           UVM_ALL_ON)
        `uvm_field_int(is_csr,               UVM_ALL_ON)
        `uvm_field_int(csr_addr,             UVM_ALL_ON | UVM_HEX)
        `uvm_field_int(csr_cmd,              UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(rs1_arch,             UVM_ALL_ON | UVM_DEC)
        `uvm_field_int(cdb_data,             UVM_ALL_ON | UVM_HEX)
    `uvm_object_utils_end

    function new(string name = "cpu_commit_item");
        super.new(name);
        clear();
    endfunction

    function void clear();
        valid        = 1'b0;
        rob_tag      = '0;
        commit_time  = 0;
        curr_phy     = '0;
        prev_phy     = '0;
        rd_addr      = '0;
        rw           = 1'b0;
        mw           = 1'b0;
        compl        = 1'b0;
        sw_addr      = '0;
        sw_strb      = '0;
        pc           = '0;
        trap_cause   = TRAP_CAUSE_NONE;
        mret_occur   = 1'b0;
        is_csr       = 1'b0;
        csr_addr     = '0;
        csr_cmd      = CSR_CMD_NONE;
        rs1_arch     = '0;
        cdb_data     = '0;
    endfunction

    // Same word index as cpu_base_item.imem_word_index() for scoreboard PC matching.
    function bit [63:0] pc_word_index();
        // Zero-extend word index (Questa lint-friendly vs. param-sized replication).
        return 64'(pc[IMEM_DEPTH-1:2]);
    endfunction

    // Populate all rob_entry fields in one call (monitor / reference model helper).
    function void set_rob_entry(
        input bit [PHY_REGISTER_FILE_WIDTH-1:0] curr_phy_in,
        input bit [PHY_REGISTER_FILE_WIDTH-1:0] prev_phy_in,
        input bit [ARCH_REG_WIDTH-1:0]          rd_addr_in,
        input bit                               rw_in,
        input bit                               mw_in,
        input bit                               compl_in,
        input bit [DMEM_DEPTH-1:0]              sw_addr_in,
        input bit [W_BYTE_NUM-1:0]              sw_strb_in,
        input bit [IMEM_DEPTH-1:0]              pc_in,
        input bit [TRAP_CAUSE_WIDTH-1:0]        trap_cause_in,
        input bit                               mret_occur_in,
        input bit                               is_csr_in,
        input bit [CSR_ADDR_WIDTH-1:0]          csr_addr_in,
        input bit [CSR_CMD_WIDTH-1:0]           csr_cmd_in,
        input bit [ARCH_REG_WIDTH-1:0]          rs1_arch_in,
        input bit [REG_FILE_DATA_WIDTH-1:0]     cdb_data_in
    );
        curr_phy     = curr_phy_in;
        prev_phy     = prev_phy_in;
        rd_addr      = rd_addr_in;
        rw           = rw_in;
        mw           = mw_in;
        compl        = compl_in;
        sw_addr      = sw_addr_in;
        sw_strb      = sw_strb_in;
        pc           = pc_in;
        trap_cause   = trap_cause_in;
        mret_occur   = mret_occur_in;
        is_csr       = is_csr_in;
        csr_addr     = csr_addr_in;
        csr_cmd      = csr_cmd_in;
        rs1_arch     = rs1_arch_in;
        cdb_data     = cdb_data_in;
    endfunction

    // Snapshot from rob_commit_monitor lat_* (one-cycle commit pulse).
    function void sample_from_commit_if(virtual cpu_commit_if #(
        ROB_INDEX_WIDTH,
        DMEM_DEPTH,
        IMEM_DEPTH,
        REG_FILE_DATA_WIDTH,
        ARCH_REG_WIDTH,
        PHY_REGISTER_FILE_WIDTH,
        W_BYTE_NUM,
        TRAP_CAUSE_WIDTH,
        CSR_ADDR_WIDTH,
        CSR_CMD_WIDTH
    ).mon_mp mon);
        if (!mon.lat_valid && !mon.rob_commit)
            return;

        valid       = 1'b1;
        commit_time = $time;

        if (mon.lat_valid) begin
            rob_tag = mon.lat_rob_tag;
            set_rob_entry(
                .curr_phy_in    (mon.lat_curr_phy),
                .prev_phy_in    (mon.lat_prev_phy),
                .rd_addr_in     (mon.lat_rd_arch),
                .rw_in          (mon.lat_reg_write),
                .mw_in          (mon.lat_mem_write),
                .compl_in       (1'b1),
                .sw_addr_in     (mon.lat_sw_addr),
                .sw_strb_in     (mon.lat_sw_strb),
                .pc_in          (mon.lat_pc),
                .trap_cause_in  (mon.lat_trap_cause),
                .mret_occur_in  (mon.lat_mret),
                .is_csr_in      (mon.lat_is_csr),
                .csr_addr_in    (mon.lat_csr_addr),
                .csr_cmd_in     (mon.lat_csr_cmd),
                .rs1_arch_in    (mon.lat_rs1_arch),
                .cdb_data_in    (mon.lat_cdb_data)
            );
        end else begin
            rob_tag = mon.mon_commit_rob_tag;
            set_rob_entry(
                .curr_phy_in    (mon.mon_curr_phy),
                .prev_phy_in    (mon.mon_prev_phy),
                .rd_addr_in     (mon.mon_rd_arch),
                .rw_in          (mon.mon_reg_write),
                .mw_in          (mon.mon_mem_write),
                .compl_in       (1'b1),
                .sw_addr_in     (mon.mon_sw_addr),
                .sw_strb_in     (mon.mon_sw_strb),
                .pc_in          (mon.mon_pc),
                .trap_cause_in  (mon.mon_trap_cause),
                .mret_occur_in  (mon.mon_mret),
                .is_csr_in      (mon.mon_is_csr),
                .csr_addr_in    (mon.mon_csr_addr),
                .csr_cmd_in     (mon.mon_csr_cmd),
                .rs1_arch_in    (mon.mon_rs1_arch),
                .cdb_data_in    (mon.mon_cdb_data)
            );
        end
    endfunction

    function string trap_cause_to_string(input bit [TRAP_CAUSE_WIDTH-1:0] cause = trap_cause);
        case (trap_cause_t'(cause))
            TRAP_CAUSE_NONE:    return "NONE";
            TRAP_CAUSE_EBREAK:  return "EBREAK";
            TRAP_CAUSE_ECALL_M: return "ECALL_M";
            default:            return $sformatf("CAUSE_%0d", cause);
        endcase
    endfunction

    function string csr_cmd_to_string(input bit [CSR_CMD_WIDTH-1:0] cmd = csr_cmd);
        case (csr_cmd_e'(cmd))
            CSR_CMD_NONE: return "NONE";
            CSR_CMD_RW:   return "RW";
            CSR_CMD_RS:   return "RS";
            CSR_CMD_RC:   return "RC";
            CSR_CMD_RWI:  return "RWI";
            CSR_CMD_RSI:  return "RSI";
            CSR_CMD_RCI:  return "RCI";
            default:      return $sformatf("CMD_%0d", cmd);
        endcase
    endfunction

    function string entry_kind_to_string();
        if (mret_occur)
            return "MRET";
        if (trap_cause != TRAP_CAUSE_NONE)
            return trap_cause_to_string();
        if (is_csr)
            return "CSR";
        if (mw)
            return "STORE";
        if (rw)
            return "REG_WRITE";
        return "OTHER";
    endfunction

    virtual function string convert2string();
        return $sformatf(
            "commit tag=%0d kind=%s pc=0x%0h rd=x%0d curr_phy=%0d prev_phy=%0d rw=%0b mw=%0b cdb=0x%0h sw_addr=0x%0h sw_strb=0x%0h csr=0x%0h/%s trap=%s mret=%0b rs1_arch=x%0d @%0t",
            rob_tag,
            entry_kind_to_string(),
            pc,
            rd_addr,
            curr_phy,
            prev_phy,
            rw,
            mw,
            cdb_data,
            sw_addr,
            sw_strb,
            csr_addr,
            csr_cmd_to_string(),
            trap_cause_to_string(),
            mret_occur,
            rs1_arch,
            commit_time
        );
    endfunction

    virtual function void do_copy(uvm_object rhs);
        cpu_commit_item #(ROB_INDEX_WIDTH, DMEM_DEPTH, IMEM_DEPTH, REG_FILE_DATA_WIDTH,
            ARCH_REG_WIDTH, PHY_REGISTER_FILE_WIDTH, W_BYTE_NUM, TRAP_CAUSE_WIDTH,
            CSR_ADDR_WIDTH, CSR_CMD_WIDTH) rhs_;

        if (!$cast(rhs_, rhs)) begin
            `uvm_fatal(get_type_name(), "do_copy: type mismatch")
        end

        valid       = rhs_.valid;
        rob_tag     = rhs_.rob_tag;
        commit_time = rhs_.commit_time;
        set_rob_entry(
            .curr_phy_in    (rhs_.curr_phy),
            .prev_phy_in    (rhs_.prev_phy),
            .rd_addr_in     (rhs_.rd_addr),
            .rw_in          (rhs_.rw),
            .mw_in          (rhs_.mw),
            .compl_in       (rhs_.compl),
            .sw_addr_in     (rhs_.sw_addr),
            .sw_strb_in     (rhs_.sw_strb),
            .pc_in          (rhs_.pc),
            .trap_cause_in  (rhs_.trap_cause),
            .mret_occur_in  (rhs_.mret_occur),
            .is_csr_in      (rhs_.is_csr),
            .csr_addr_in    (rhs_.csr_addr),
            .csr_cmd_in     (rhs_.csr_cmd),
            .rs1_arch_in    (rhs_.rs1_arch),
            .cdb_data_in    (rhs_.cdb_data)
        );
    endfunction

    virtual function bit do_compare(uvm_object rhs, uvm_comparer comparer);
        cpu_commit_item #(ROB_INDEX_WIDTH, DMEM_DEPTH, IMEM_DEPTH, REG_FILE_DATA_WIDTH,
            ARCH_REG_WIDTH, PHY_REGISTER_FILE_WIDTH, W_BYTE_NUM, TRAP_CAUSE_WIDTH,
            CSR_ADDR_WIDTH, CSR_CMD_WIDTH) rhs_;
        bit same;

        same = super.do_compare(rhs, comparer);
        if (!$cast(rhs_, rhs))
            return 1'b0;

        same &= (valid       === rhs_.valid);
        same &= (rob_tag     === rhs_.rob_tag);
        same &= (curr_phy    === rhs_.curr_phy);
        same &= (prev_phy    === rhs_.prev_phy);
        same &= (rd_addr     === rhs_.rd_addr);
        same &= (rw          === rhs_.rw);
        same &= (mw          === rhs_.mw);
        same &= (compl       === rhs_.compl);
        same &= (sw_addr     === rhs_.sw_addr);
        same &= (sw_strb     === rhs_.sw_strb);
        same &= (pc          === rhs_.pc);
        same &= (trap_cause  === rhs_.trap_cause);
        same &= (mret_occur  === rhs_.mret_occur);
        same &= (is_csr      === rhs_.is_csr);
        same &= (csr_addr    === rhs_.csr_addr);
        same &= (csr_cmd     === rhs_.csr_cmd);
        same &= (rs1_arch    === rhs_.rs1_arch);
        same &= (cdb_data    === rhs_.cdb_data);

        return same;
    endfunction

endclass
