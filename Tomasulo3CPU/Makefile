# ============================================================
#  Generic SystemVerilog testbench flow
#
#  Usage:
#    make sim PROJECT=IFQ
#    make gui PROJECT=IFQ
#    make clean PROJECT=IFQ
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

# ---- paths ----
PROJ_DIR  := $(shell pwd)
SRC_DIR   := $(PROJ_DIR)/src
TB_DIR    := $(PROJ_DIR)/tb
BUILD_DIR := $(PROJ_DIR)/build/$(PROJECT)

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

# DW IP behavioral stubs for simulators without Synopsys DesignWare
DW_STUB_FILE := $(TB_DIR)/dw_ip_stubs.sv

TB_FILES := \
	$(TB_DIR)/$(PROJECT)_tb.sv

# ---- VCS options ----
VCS_OPTS := \
	-full64 \
	-sverilog \
	-debug_access+all \
	-timescale=1ns/1ps \
	+define+FSDB_DUMP \
	+define+DW_SUPPRESS_WARN \
	+lint=all

ifeq ($(USE_DW),1)
VCS_OPTS += +incdir+$(DW_SIM_DIR)
endif

# ---- Verdi options ----
VERDI_FILES := $(SRC_FILES) $(TB_FILES)
VERDI_OPTS  := -sv

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
	@test -f "$(TB_DIR)/$(PROJECT)_tb.sv" || \
		(echo "[ERROR] Missing TB file: $(TB_DIR)/$(PROJECT)_tb.sv"; exit 1)
ifeq ($(USE_DW),1)
	@test -d "$(DW_SIM_DIR)" || \
		(echo "[ERROR] Missing DesignWare sim directory: $(DW_SIM_DIR)"; exit 1)
	@for file in $(DW_SIM_FILES); do \
		test -f "$$file" || \
			(echo "[ERROR] Missing DesignWare sim model: $$file"; exit 1); \
	done
endif

# ---- compile ----
.PHONY: compile
compile: check
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
		$(PLUSARGS) \
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
	cd $(QUESTA_BUILD) && vlog -sv -timescale "1ns/1ps" \
		$(PKG_FILES) \
		$(DW_STUB_FILE) \
		$(NON_PKG_SRC_FILES) \
		$(TB_FILES) \
		2>&1 | tee compile.log
	cd $(QUESTA_BUILD) && vsim -c -do "run -all; quit -f" \
		$(TOP_MODULE) \
		$(PLUSARGS) \
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
	cd $(QUESTA_BUILD) && vlog -sv -timescale "1ns/1ps" \
		$(PKG_FILES) \
		$(DW_STUB_FILE) \
		$(NON_PKG_SRC_FILES) \
		$(TB_FILES)
	cd $(QUESTA_BUILD) && vsim -gui $(TOP_MODULE) &
