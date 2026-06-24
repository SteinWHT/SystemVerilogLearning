# ============================================================
#  Generic SystemVerilog testbench flow
#
#  Usage:
#    make sim PROJECT=IFQ
#    make gui PROJECT=IFQ
#    make clean PROJECT=IFQ
#    make uvm UVM_TEST=cpu_int_alu_test
#    make uvm-gui UVM_TEST=cpu_int_alu_test
#
#  Assumption:
#    TB file: tb/$(PROJECT)_tb.sv
#    TB top:  $(PROJECT)_tb
#
#  You manually edit SRC_FILES for each test.
# ============================================================

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

PROJECT ?= IFQ
UVM_TEST ?= cpu_int_alu_test
UVM_DUT ?= legacy
COV ?= 0
COV_DUT ?= legacy
# VCS -cm: group/covergroups are merged/reported by URG (-metric group), not at compile.
COV_METRICS ?= line+cond+fsm+tgl+branch+assert
COV_NAME ?= $(PROJECT)_$(UVM_TEST)
COV_INPUTS ?= $(PROJ_DIR)/build/uvm_cov/*.vdb
COV_MERGE_DIR ?= $(PROJ_DIR)/build/uvm_cov_merged.vdb
COV_REPORT_DIR ?= $(PROJ_DIR)/build/uvm_cov_report
# C-suite only — use uvm-cov-merge-baremetal after covergroup edits (avoids stale arch-test shapes)
BAREMETAL_COV_TESTS := csr_trap deep_recursion fibonacci_stress linked_list matrix_cache_stress matrix_multiply memcpy memset recursion strcmp strlen wide_data
BAREMETAL_COV_VDBS := $(foreach t,$(BAREMETAL_COV_TESTS),$(PROJ_DIR)/build/uvm_cov/uvm_$(COV_DUT)_$(t).vdb)
URG_LICENSE ?= 27000@127.0.0.1
SHIM_LIB = $(PROJ_DIR)/tools/libsnpsmalloc_shim/libsnpsmalloc_shim.so
URG_ENV = SNPSLMD_LICENSE_FILE=$(URG_LICENSE) LM_LICENSE_FILE=$(URG_LICENSE) SYNOPSYS_LICENSE_FILE=$(URG_LICENSE) LD_LIBRARY_PATH= LD_PRELOAD=$(SHIM_LIB)
URG_METRICS ?= line+cond+fsm+tgl+branch+assert+group
# Sign-off: score the selected UVM top/DUT in modlist.html; UVM package and Verdi hooks are TB collateral.
URG_EXTRA ?=
URG_OPTS := -full64 -metric $(URG_METRICS) $(URG_EXTRA)

# ---- paths ----
PROJ_DIR  := $(shell pwd)
SRC_DIR   := $(PROJ_DIR)/src
TB_DIR    := $(PROJ_DIR)/tb
UVM_DIR   := $(PROJ_DIR)/uvm
BUILD_DIR := $(PROJ_DIR)/build/$(PROJECT)
ifeq ($(PROJECT),uvm)
BUILD_DIR := $(PROJ_DIR)/build/uvm_$(UVM_DUT)
endif
UVM_INC_DIRS := \
	+incdir+$(UVM_DIR) \
	+incdir+$(UVM_DIR)/agent \
	+incdir+$(UVM_DIR)/env \
	+incdir+$(UVM_DIR)/items \
	+incdir+$(UVM_DIR)/seq \
	+incdir+$(UVM_DIR)/tests \
	+incdir+$(UVM_DIR)/scoreboard \
	+incdir+$(UVM_DIR)/ref \
	+incdir+$(UVM_DIR)/cov \
	+incdir+$(UVM_DIR)/utils \
	+incdir+$(UVM_DIR)/dpi

# ---- Spike DPI-C golden model (constrained-random lockstep co-sim) ----
# Enable with ENABLE_SPIKE_DPI=1, e.g.
#   make uvm UVM_TEST=cpu_constrained_random_test ENABLE_SPIKE_DPI=1
#
# The shim and Spike are C++17. If the default `g++` is too old (e.g. it
# rejects `-std=c++17`), point CXX at the same C++17 compiler that built Spike:
#   make spike-cosim-lib ENABLE_SPIKE_DPI=1 CXX=g++-9
# or override the standard flag for compilers that only know the old spelling:
#   make spike-cosim-lib ENABLE_SPIKE_DPI=1 SPIKE_CXXSTD=c++1z
# IMPORTANT: this .so is dlopen'd by simv at *run* time, so build it in the
# same environment VCS runs in (e.g. inside the Docker container), with a
# C++17 compiler. To keep the .so loadable on an old system libstdc++, link the
# C++ runtime statically:
#   make spike-cosim-lib ENABLE_SPIKE_DPI=1 \
#     CXX=/data/tools/Xilinx/Vitis_HLS/2024.1/tps/lnx64/gcc-9.3.0/bin/g++-9.3.0 \
#     SPIKE_EXTRA_LDFLAGS="-static-libstdc++ -static-libgcc"
ENABLE_SPIKE_DPI ?= 0
CXX              ?= g++
SPIKE_CXXSTD     ?= c++17
SPIKE_CXXFLAGS   ?=
SPIKE_EXTRA_LDFLAGS ?=
SPIKE_SRC_DIR    := $(PROJ_DIR)/tools/riscv-isa-sim
SPIKE_LIB_DIR    := $(SPIKE_SRC_DIR)/build
SPIKE_COSIM_DIR  := $(UVM_DIR)/tools/spike_cosim
SPIKE_COSIM_LIB  := $(SPIKE_COSIM_DIR)/libspike_cosim.so
SPIKE_LDFLAGS    := -L$(SPIKE_COSIM_DIR) -lspike_cosim \
	-Wl,-rpath,$(SPIKE_COSIM_DIR) -Wl,-rpath,$(SPIKE_LIB_DIR)
SPIKE_DPI_PKG    :=
SPIKE_DPI_DEP    :=
ifeq ($(ENABLE_SPIKE_DPI),1)
SPIKE_DPI_PKG    := $(UVM_DIR)/dpi/cpu_spike_dpi_pkg.sv
SPIKE_DPI_DEP    := $(SPIKE_COSIM_LIB)
endif

# ---- Synopsys DesignWare simulation library ----
# Override these from the command line if your Synopsys install moves:
#   make sim DC_HOME=/path/to/syn/V-2023.12-SP3
#   make sim DW_HOME=/path/to/dw
USE_DW     ?= 1
DC_HOME    ?= /home/synopsys/syn/V-2023.12-SP3
DW_HOME    ?= $(DC_HOME)/dw
DW_SIM_DIR := $(DW_HOME)/sim_ver
DW_SIM_FILES := \
	$(DW_SIM_DIR)/DW02_mult_4_stage.v \
	$(DW_SIM_DIR)/DW_div_seq.v

# ---- derived names ----
TOP_MODULE := $(PROJECT)_tb
FSDB_FILE  := $(PROJECT).fsdb
ifeq ($(PROJECT),uvm)
FSDB_FILE := uvm_$(UVM_DUT).fsdb
endif

# ============================================================
#  Manually add RTL source files here
# ============================================================

SRC_FILES := \
	$(SRC_DIR)/riscv_funct_pkg.sv \
	$(SRC_DIR)/riscv_opcode_pkg.sv \
	$(SRC_DIR)/riscv_types_pkg.sv \
	$(SRC_DIR)/simple_module/sync_fifo.sv \
	$(SRC_DIR)/simple_module/dual_port_memory.sv \
	$(SRC_DIR)/simple_module/sync_lifo.sv \
	$(SRC_DIR)/IFQ.sv \
	$(SRC_DIR)/BPB.sv \
	$(SRC_DIR)/RAS.sv \
	$(SRC_DIR)/FRL.sv \
	$(SRC_DIR)/FRAT.sv \
	$(SRC_DIR)/ROB.sv \
	$(SRC_DIR)/RBA.sv \
	$(SRC_DIR)/RRAT.sv \
	$(SRC_DIR)/SB.sv \
	$(SRC_DIR)/RISC_V_DECODER.sv \
	$(SRC_DIR)/DISPATCH.sv \
	$(SRC_DIR)/CPU_FRONT_END.sv \
	$(SRC_DIR)/back_end/ISSUE_QUEUE/INTQ.sv \
	$(SRC_DIR)/back_end/ISSUE_QUEUE/MULQ.sv \
	$(SRC_DIR)/back_end/ISSUE_QUEUE/DIVQ.sv \
	$(SRC_DIR)/back_end/ISSUE_QUEUE/LSQ.sv \
	$(SRC_DIR)/back_end/ISSUE_QUEUE/ISSUEQ.sv \
	$(SRC_DIR)/back_end/LSB.sv \
	$(SRC_DIR)/back_end/ISSUEUNIT.sv \
	$(SRC_DIR)/back_end/PRF.sv \
	$(SRC_DIR)/back_end/EXE/ALU.sv \
	$(SRC_DIR)/back_end/EXE/DIV.sv \
	$(SRC_DIR)/back_end/EXE/MUL.sv \
	$(SRC_DIR)/back_end/EXE/EXE.sv \
	$(SRC_DIR)/back_end/CDB.sv \
	$(SRC_DIR)/back_end/CPU_BACK_END.sv \
	$(SRC_DIR)/CSR.sv \
	$(SRC_DIR)/CPU.sv \

# ---- L1 D-cache (sibling L1DCache project) ----
# Enable with USE_DCACHE=1 (auto-enabled for PROJECT=CPU_dcache_c).  The cache
# replaces the inline behavioural dmem in the data-memory testbench.
L1DCACHE_DIR ?= $(PROJ_DIR)/../L1DCache
DCACHE_FILES := \
	$(L1DCACHE_DIR)/rtl/dcache_pkg.sv \
	$(L1DCACHE_DIR)/rtl/dcache_if.sv \
	$(L1DCACHE_DIR)/rtl/dcache_plru.sv \
	$(L1DCACHE_DIR)/rtl/dcache_tag_ram.sv \
	$(L1DCACHE_DIR)/rtl/dcache_data_ram.sv \
	$(L1DCACHE_DIR)/rtl/dcache_mshr.sv \
	$(L1DCACHE_DIR)/rtl/dcache_refill.sv \
	$(L1DCACHE_DIR)/rtl/dcache_core.sv \
	$(L1DCACHE_DIR)/rtl/dcache_top.sv \
	$(L1DCACHE_DIR)/tb/dcache_backing_mem.sv \
	$(L1DCACHE_DIR)/integration/dcache_tomasulo_wrap.sv

# ---- L1 I-cache (sibling L1ICache project) ----
L1ICACHE_DIR ?= $(PROJ_DIR)/../L1ICache
ICACHE_FILES := 	$(L1ICACHE_DIR)/rtl/icache_pkg.sv 	$(L1ICACHE_DIR)/rtl/icache_if.sv 	$(L1ICACHE_DIR)/rtl/icache_plru.sv 	$(L1ICACHE_DIR)/rtl/icache_tag_ram.sv 	$(L1ICACHE_DIR)/rtl/icache_data_ram.sv 	$(L1ICACHE_DIR)/rtl/icache_mshr.sv 	$(L1ICACHE_DIR)/rtl/icache_refill.sv 	$(L1ICACHE_DIR)/rtl/icache_core.sv 	$(L1ICACHE_DIR)/rtl/icache_top.sv 	$(L1ICACHE_DIR)/rtl/icache_axi_master_bridge.sv

# ---- Full AXI4 memory subsystem (sibling AXISoC project) ----
AXISOC_DIR ?= $(PROJ_DIR)/../AXISoC
AXI_FILES := \
	$(AXISOC_DIR)/rtl/pkg/axi_pkg.sv \
	$(AXISOC_DIR)/rtl/intf/axi_if.sv \
	$(AXISOC_DIR)/rtl/slave/axi_sram.sv \
	$(AXISOC_DIR)/rtl/interconnect/axi_xbar_2x1.sv \
	$(AXISOC_DIR)/rtl/top/axi_full_soc_top.sv \
	$(L1DCACHE_DIR)/integration/dcache_axi_master_bridge.sv

USE_DCACHE ?= 0
ifeq ($(PROJECT),CPU_dcache_c)
USE_DCACHE := 1
endif
ifeq ($(PROJECT),CPU_dcache_axi)
USE_DCACHE := 1
endif
ifeq ($(PROJECT),uvm)
USE_DCACHE := 1
endif
ifeq ($(USE_DCACHE),1)
SRC_FILES += $(DCACHE_FILES) $(SRC_DIR)/CPU_L1DCache.sv
endif

USE_AXI ?= 0
ifeq ($(PROJECT),CPU_dcache_axi)
USE_AXI := 1
endif
ifeq ($(PROJECT),uvm)
ifeq ($(UVM_DUT),axi)
USE_AXI := 1
else ifneq ($(UVM_DUT),legacy)
$(error Unsupported UVM_DUT '$(UVM_DUT)'; use legacy or axi)
endif
endif
ifeq ($(USE_AXI),1)
SRC_FILES += $(AXI_FILES) $(ICACHE_FILES) \
	$(SRC_DIR)/cache_coherence_ctrl.sv \
	$(SRC_DIR)/CPU_L1DCache_AXI.sv
endif

# DW IP behavioral stubs for simulators without Synopsys DesignWare
DW_STUB_FILE := $(TB_DIR)/dw_ip_stubs.sv

ifeq ($(PROJECT),uvm)
ifeq ($(UVM_DUT),axi)
TOP_MODULE := tb_top_axi
UVM_TOP_FILE := $(UVM_DIR)/tb_top_axi.sv
else
TOP_MODULE := tb_top
UVM_TOP_FILE := $(UVM_DIR)/tb_top.sv
endif
TB_FILES := \
	$(UVM_DIR)/cpu_if.sv \
	$(UVM_DIR)/cpu_commit_if.sv \
	$(UVM_DIR)/cpu_coherence_if.sv \
	$(TB_DIR)/rob_commit_bind.sv \
	$(SPIKE_DPI_PKG) \
	$(UVM_DIR)/cpu_pkg.sv \
	$(UVM_TOP_FILE)
else
TB_FILES := \
	$(TB_DIR)/$(PROJECT)_tb.sv
ifneq ($(findstring CPU,$(PROJECT)),)
TB_FILES += $(TB_DIR)/rob_commit_bind.sv
endif
endif

# ---- VCS options ----
VCS_OPTS := \
	-full64 \
	-sverilog \
	-debug_access+all \
	-timescale=1ns/1ps \
	+define+FSDB_DUMP \
	+define+DW_SUPPRESS_WARN \
	+lint=all

ifeq ($(PROJECT),uvm)
VCS_OPTS += -ntb_opts uvm $(UVM_INC_DIRS)
ifeq ($(ENABLE_SPIKE_DPI),1)
VCS_OPTS += +define+CPU_SPIKE_DPI -LDFLAGS "$(SPIKE_LDFLAGS)"
endif
endif

ifeq ($(USE_DW),1)
VCS_OPTS += +incdir+$(DW_SIM_DIR)
endif

ifeq ($(COV),1)
VCS_OPTS += -cm $(COV_METRICS) -cm_dir simv.vdb
RUN_COV_OPTS := -cm $(COV_METRICS) -cm_dir simv.vdb -cm_name $(COV_NAME)
else
RUN_COV_OPTS :=
endif

# ---- Verdi options ----
VERDI_FILES := $(SRC_FILES) $(TB_FILES)
VERDI_OPTS  := -sv

ifeq ($(PROJECT),uvm)
VERDI_OPTS  += -ntb_opts uvm $(UVM_INC_DIRS)
endif

RUN_PLUSARGS := $(PLUSARGS)
ifeq ($(PROJECT),uvm)
RUN_PLUSARGS += +UVM_TESTNAME=$(UVM_TEST)
endif

ifeq ($(USE_DW),1)
VERDI_FILES := $(DW_SIM_FILES) $(VERDI_FILES)
VERDI_OPTS  += +incdir+$(DW_SIM_DIR)
endif

# ---- default target ----
.PHONY: all
all: sim

# ---- check testbench exists ----
.PHONY: check
check:
ifeq ($(PROJECT),uvm)
	@test -f "$(UVM_TOP_FILE)" || \
		(echo "[ERROR] Missing UVM TB top: $(UVM_TOP_FILE)"; exit 1)
	@for file in $(TB_FILES); do \
		test -f "$$file" || \
			(echo "[ERROR] Missing UVM/TB file: $$file"; exit 1); \
	done
else
	@test -f "$(TB_DIR)/$(PROJECT)_tb.sv" || \
		(echo "[ERROR] Missing TB file: $(TB_DIR)/$(PROJECT)_tb.sv"; exit 1)
endif
ifeq ($(USE_DW),1)
	@test -d "$(DW_SIM_DIR)" || \
		(echo "[ERROR] Missing DesignWare sim directory: $(DW_SIM_DIR)"; exit 1)
	@for file in $(DW_SIM_FILES); do \
		test -f "$$file" || \
			(echo "[ERROR] Missing DesignWare sim model: $$file"; exit 1); \
	done
endif

# ---- compile ----
# ---- Spike DPI-C golden-model shared library ----
$(SPIKE_COSIM_LIB): $(SPIKE_COSIM_DIR)/spike_cosim.cc $(SPIKE_COSIM_DIR)/spike_cosim.h
	@echo "  Building Spike DPI-C co-sim library"
	@test -d "$(SPIKE_LIB_DIR)" || \
		(echo "[ERROR] Spike not built at $(SPIKE_LIB_DIR). Build tools/riscv-isa-sim first."; exit 1)
	$(CXX) -std=$(SPIKE_CXXSTD) -O2 -fPIC -shared $(SPIKE_CXXFLAGS) -I$(SPIKE_SRC_DIR) \
		-o $@ $(SPIKE_COSIM_DIR)/spike_cosim.cc \
		-L$(SPIKE_LIB_DIR) -lriscv -ldisasm -lsoftfloat -lfesvr -lfdt \
		-Wl,-rpath,$(SPIKE_LIB_DIR) $(SPIKE_EXTRA_LDFLAGS)

.PHONY: spike-cosim-lib
spike-cosim-lib: $(SPIKE_COSIM_LIB)

.PHONY: compile
compile: check $(SPIKE_DPI_DEP)
	@mkdir -p $(BUILD_DIR)
	@echo "============================================"
	@echo "  Project: $(PROJECT)"
	@echo "  Top:     $(TOP_MODULE)"
	@echo "  Build:   $(BUILD_DIR)"
ifeq ($(USE_DW),1)
	@echo "  DW lib:  $(DW_SIM_DIR)"
endif
	@echo "  Compiling with VCS"
	@echo "============================================"
	@if [ ! -x "$(BUILD_DIR)/simv" ] && [ -f "$(BUILD_DIR)/simv.daidir/.vcs.timestamp" ]; then \
		echo "[WARN] Found stale VCS cache without simv; forcing relink."; \
		rm -f "$(BUILD_DIR)/simv.daidir/.vcs.timestamp"; \
	fi
	cd $(BUILD_DIR) && vcs $(VCS_OPTS) \
		$(if $(filter 1,$(USE_DW)),$(DW_SIM_FILES)) \
		$(SRC_FILES) $(TB_FILES) \
		-top $(TOP_MODULE) \
		-o simv \
		-l compile.log \
		2>&1 | tee compile_screen.log
	@test -x "$(BUILD_DIR)/simv" || \
		(echo "[ERROR] VCS did not create $(BUILD_DIR)/simv. Check $(BUILD_DIR)/compile.log"; exit 1)

# ---- simulate ----
.PHONY: sim
sim: compile
	@echo ""
	@echo "============================================"
	@echo "  Running simulation"
	@echo "============================================"
	@test -x "$(BUILD_DIR)/simv" || \
		(echo "[ERROR] Missing simulator executable: $(BUILD_DIR)/simv"; exit 1)
	cd $(BUILD_DIR) && ./simv -l sim.log +fsdbfile+$(FSDB_FILE) \
		$(RUN_COV_OPTS) \
		$(RUN_PLUSARGS) \
		2>&1 | tee sim_screen.log
	@echo ""
	@echo "============================================"
	@echo "  Simulation finished — see $(BUILD_DIR)/sim.log"
	@echo "============================================"

# ---- open Verdi ----
.PHONY: gui
gui: sim
	@echo "Opening Verdi..."
	cd $(BUILD_DIR) && verdi -ssf $(FSDB_FILE) $(VERDI_OPTS) \
		$(VERDI_FILES) \
		-top $(TOP_MODULE) &

.PHONY: uvm uvm-compile uvm-gui uvm-axi uvm-axi-compile uvm-axi-gui
uvm:
	$(MAKE) PROJECT=uvm sim

uvm-compile:
	$(MAKE) PROJECT=uvm compile

uvm-gui:
	$(MAKE) PROJECT=uvm gui

uvm-axi:
	$(MAKE) PROJECT=uvm UVM_DUT=axi sim

uvm-axi-compile:
	$(MAKE) PROJECT=uvm UVM_DUT=axi compile

uvm-axi-gui:
	$(MAKE) PROJECT=uvm UVM_DUT=axi gui

$(SHIM_LIB): $(PROJ_DIR)/tools/libsnpsmalloc_shim/libsnpsmalloc_shim.c
	@mkdir -p $(dir $@)
	gcc -shared -fPIC -O2 -o $@ $< -ldl

.PHONY: uvm-cov-merge
uvm-cov-merge: $(SHIM_LIB)
	@mkdir -p $(dir $(COV_REPORT_DIR))
	$(URG_ENV) urg $(URG_OPTS) -dir $(COV_INPUTS) -dbname $(COV_MERGE_DIR) -report $(COV_REPORT_DIR)

.PHONY: uvm-cov-merge-baremetal
uvm-cov-merge-baremetal: $(SHIM_LIB)
	@mkdir -p $(dir $(COV_REPORT_DIR))
	@for vdb in $(BAREMETAL_COV_VDBS); do \
		test -d "$$vdb" || (echo "[ERROR] Missing $$vdb — rerun: python3 uvm/tools/run_baremetal_spike.py --coverage all"; exit 1); \
	done
	$(URG_ENV) urg $(URG_OPTS) -dir $(BAREMETAL_COV_VDBS) -dbname $(COV_MERGE_DIR) -report $(COV_REPORT_DIR)

.PHONY: uvm-cov-report
uvm-cov-report: $(SHIM_LIB)
	@mkdir -p $(dir $(COV_REPORT_DIR))
	$(URG_ENV) urg $(URG_OPTS) -dir $(COV_INPUTS) -report $(COV_REPORT_DIR)

# ---- clean current project ----
.PHONY: clean
clean:
	@echo "[clean] Removing $(BUILD_DIR)"
	rm -rf $(BUILD_DIR)

# ---- clean all build artifacts ----
.PHONY: clean-all
clean-all:
	@echo "[clean-all] Removing $(PROJ_DIR)/build"
	rm -rf $(PROJ_DIR)/build

# ---- synthesis with Design Compiler (ASAP7 7nm) ----
.PHONY: synth
synth:
	@echo "============================================"
	@echo "  Running Synthesis with Design Compiler (ASAP7 7nm)"
	@echo "  CLK_PERIOD: $(if $(CLK_PERIOD),$(CLK_PERIOD),3.0) ns"
	@echo "============================================"
	@mkdir -p $(PROJ_DIR)/synth
	@mkdir -p $(PROJ_DIR)/report
	cd $(PROJ_DIR) && dc_shell -x "set argv {CPU $(if $(CLK_PERIOD),$(CLK_PERIOD),3.0)}" -f script/synth_asap7.tcl 2>&1 | tee synth/synthesis.log

# ============================================================
#  QuestaSim / ModelSim targets  (USE_DW=0 by default, uses stubs)
# ============================================================

QUESTA_BUILD := $(PROJ_DIR)/build/questa_$(PROJECT)
QUESTA_WORK  := $(QUESTA_BUILD)/work

QUESTA_VLOG_OPTS := -sv -timescale "1ns/1ps"
ifeq ($(PROJECT),uvm)
QUESTA_VLOG_OPTS += -uvm $(UVM_INC_DIRS)
endif

PKG_FILES := \
	$(SRC_DIR)/riscv_funct_pkg.sv \
	$(SRC_DIR)/riscv_opcode_pkg.sv \
	$(SRC_DIR)/riscv_types_pkg.sv

NON_PKG_SRC_FILES := $(filter-out $(PKG_FILES),$(SRC_FILES))

.PHONY: sim-questa
sim-questa: check
	@mkdir -p $(QUESTA_BUILD)
	@echo "============================================"
	@echo "  QuestaSim: $(PROJECT)"
	@echo "  Top:       $(TOP_MODULE)"
	@echo "  Build:     $(QUESTA_BUILD)"
	@echo "============================================"
	cd $(QUESTA_BUILD) && vlib work 2>/dev/null; true
	cd $(QUESTA_BUILD) && vlog $(QUESTA_VLOG_OPTS) \
		$(PKG_FILES) \
		$(DW_STUB_FILE) \
		$(NON_PKG_SRC_FILES) \
		$(TB_FILES) \
		2>&1 | tee compile.log
	cd $(QUESTA_BUILD) && vsim -c -do "run -all; quit -f" \
		$(TOP_MODULE) \
		$(RUN_PLUSARGS) \
		2>&1 | tee sim.log
	@echo ""
	@echo "============================================"
	@echo "  QuestaSim simulation finished"
	@echo "  See $(QUESTA_BUILD)/sim.log"
	@echo "============================================"

.PHONY: gui-questa
gui-questa: check
	@mkdir -p $(QUESTA_BUILD)
	cd $(QUESTA_BUILD) && vlib work 2>/dev/null; true
	cd $(QUESTA_BUILD) && vlog $(QUESTA_VLOG_OPTS) \
		$(PKG_FILES) \
		$(DW_STUB_FILE) \
		$(NON_PKG_SRC_FILES) \
		$(TB_FILES)
	cd $(QUESTA_BUILD) && vsim -gui $(TOP_MODULE) &
