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

PROJECT ?= IFQ

# ---- paths ----
PROJ_DIR  := $(shell pwd)
SRC_DIR   := $(PROJ_DIR)/src
TB_DIR    := $(PROJ_DIR)/tb
BUILD_DIR := $(PROJ_DIR)/build/$(PROJECT)

# ---- derived names ----
TOP_MODULE := $(PROJECT)_tb
FSDB_FILE  := $(PROJECT).fsdb

# ============================================================
#  Manually add RTL source files here
# ============================================================

SRC_FILES := \
	$(SRC_DIR)/simple_module/sync_fifo.sv \
	$(SRC_DIR)/IFQ.sv

TB_FILES := \
	$(TB_DIR)/$(PROJECT)_tb.sv

# ---- VCS options ----
VCS_OPTS := \
	-full64 \
	-sverilog \
	-debug_access+all \
	-timescale=1ns/1ps \
	+define+FSDB_DUMP \
	+lint=all

# ---- default target ----
.PHONY: all
all: sim

# ---- check testbench exists ----
.PHONY: check
check:
	@test -f "$(TB_DIR)/$(PROJECT)_tb.sv" || \
		(echo "[ERROR] Missing TB file: $(TB_DIR)/$(PROJECT)_tb.sv"; exit 1)

# ---- compile ----
.PHONY: compile
compile: check
	@mkdir -p $(BUILD_DIR)
	@echo "============================================"
	@echo "  Project: $(PROJECT)"
	@echo "  Top:     $(TOP_MODULE)"
	@echo "  Build:   $(BUILD_DIR)"
	@echo "  Compiling with VCS"
	@echo "============================================"
	cd $(BUILD_DIR) && vcs $(VCS_OPTS) \
		$(SRC_FILES) $(TB_FILES) \
		-top $(TOP_MODULE) \
		-o simv \
		-l compile.log \
		2>&1 | tee compile_screen.log

# ---- simulate ----
.PHONY: sim
sim: compile
	@echo ""
	@echo "============================================"
	@echo "  Running simulation"
	@echo "============================================"
	cd $(BUILD_DIR) && ./simv -l sim.log +fsdbfile+$(FSDB_FILE) \
		2>&1 | tee sim_screen.log
	@echo ""
	@echo "============================================"
	@echo "  Simulation finished — see $(BUILD_DIR)/sim.log"
	@echo "============================================"

# ---- open Verdi ----
.PHONY: gui
gui: sim
	@echo "Opening Verdi..."
	cd $(BUILD_DIR) && verdi -ssf $(FSDB_FILE) -sv \
		$(SRC_FILES) $(TB_FILES) \
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