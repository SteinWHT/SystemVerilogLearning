# AXISoC simulation Makefile
#
# Usage:
#   make sim PROJECT=axi_lite_sram
#   make sim PROJECT=axi_lite_sys
#   make sim PROJECT=axi_sram        # full AXI4 bursts
#   make sim PROJECT=axi_sys
#   make clean
#
# Simulator priority: vlog/vsim (Questa) > vcs > iverilog

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

PROJECT  ?= axi_lite_sram
PROJ_DIR := $(shell pwd)
BUILD_DIR := $(PROJ_DIR)/build/$(PROJECT)

TOP_MODULE := $(PROJECT)_tb

RTL_LITE := \
	$(PROJ_DIR)/rtl/pkg/axi_pkg.sv \
	$(PROJ_DIR)/rtl/intf/axi_lite_if.sv \
	$(PROJ_DIR)/rtl/slave/axi_lite_sram.sv \
	$(PROJ_DIR)/rtl/interconnect/axi_lite_xbar_2x1.sv \
	$(PROJ_DIR)/rtl/top/axi_soc_top.sv \
	$(PROJ_DIR)/tb/axi_master_bfm.sv \
	$(PROJ_DIR)/sva/axi_lite_assertions.sv

RTL_FULL := \
	$(PROJ_DIR)/rtl/pkg/axi_pkg.sv \
	$(PROJ_DIR)/rtl/intf/axi_if.sv \
	$(PROJ_DIR)/rtl/slave/axi_sram.sv \
	$(PROJ_DIR)/rtl/interconnect/axi_xbar_2x1.sv \
	$(PROJ_DIR)/rtl/top/axi_full_soc_top.sv \
	$(PROJ_DIR)/tb/axi_burst_master_bfm.sv \
	$(PROJ_DIR)/sva/axi_assertions.sv

LITE_PROJECTS := axi_lite_sram axi_lite_sys
FULL_PROJECTS := axi_sram axi_sys

ifeq ($(filter $(PROJECT),$(FULL_PROJECTS)),$(PROJECT))
  RTL_COMMON := $(RTL_FULL)
else
  RTL_COMMON := $(RTL_LITE)
endif

TB_FILE := $(PROJ_DIR)/tb/$(TOP_MODULE).sv
TIMESCALE_FILE := $(PROJ_DIR)/tb/timescale.v
VCS_TIMESCALE := -timescale=1ns/1ps

QUESTA := $(shell command -v vlog 2>/dev/null)
VCS    := $(shell command -v vcs 2>/dev/null)
IVERILOG := $(shell command -v iverilog 2>/dev/null)

.PHONY: sim gui clean help

help:
	@echo "Targets: sim, gui, clean"
	@echo "Lite:  PROJECT=axi_lite_sram | axi_lite_sys"
	@echo "Full:  PROJECT=axi_sram | axi_sys"

sim: $(BUILD_DIR)
ifeq ($(QUESTA),)
ifeq ($(VCS),)
ifeq ($(IVERILOG),)
	$(error No simulator found: install Questa (vlog/vsim), VCS, or iverilog)
else
	@echo "==> iverilog (limited SV; Questa/VCS recommended)"
	cd $(BUILD_DIR) && iverilog -g2012 -o sim.vvp \
		$(RTL_COMMON) $(TB_FILE) && vvp sim.vvp
endif
else
	@echo "==> VCS"
	cd $(BUILD_DIR) && vcs -full64 -sverilog $(VCS_TIMESCALE) +incdir+$(PROJ_DIR)/rtl/pkg \
		$(TIMESCALE_FILE) $(RTL_COMMON) $(TB_FILE) -top $(TOP_MODULE) -o simv && ./simv
endif
else
	@echo "==> QuestaSim ($(PROJECT))"
	cd $(BUILD_DIR) && vlog -sv +incdir+$(PROJ_DIR)/rtl/pkg \
		$(TIMESCALE_FILE) $(RTL_COMMON) $(TB_FILE)
	cd $(BUILD_DIR) && vsim -c $(TOP_MODULE) -do "run -all; exit"
endif

gui: $(BUILD_DIR)
	@test -n "$(QUESTA)" || $(error Questa required for gui target)
	cd $(BUILD_DIR) && vlog -sv +incdir+$(PROJ_DIR)/rtl/pkg \
		$(TIMESCALE_FILE) $(RTL_COMMON) $(TB_FILE)
	cd $(BUILD_DIR) && vsim $(TOP_MODULE)

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

clean:
	rm -rf $(PROJ_DIR)/build
