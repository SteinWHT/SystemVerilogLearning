# L1ICache simulation Makefile
#
# Usage:
#   make sim PROJECT=icache_plru
#   make sim PROJECT=icache_core
#   make clean

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

PROJECT   ?= icache_core
PROJ_DIR  := $(shell pwd)
BUILD_DIR := $(PROJ_DIR)/build/$(PROJECT)
TOP_MODULE := $(PROJECT)_tb

RTL_PKG := $(PROJ_DIR)/rtl/icache_pkg.sv

RTL_CORE := \
	$(RTL_PKG) \
	$(PROJ_DIR)/rtl/icache_if.sv \
	$(PROJ_DIR)/rtl/icache_plru.sv \
	$(PROJ_DIR)/rtl/icache_tag_ram.sv \
	$(PROJ_DIR)/rtl/icache_data_ram.sv \
	$(PROJ_DIR)/rtl/icache_mshr.sv \
	$(PROJ_DIR)/rtl/icache_refill.sv \
	$(PROJ_DIR)/rtl/icache_core.sv \
	$(PROJ_DIR)/rtl/icache_top.sv

RTL_CORE_TB := $(RTL_CORE) $(PROJ_DIR)/tb/icache_backing_mem.sv

ifdef USE_SVA
RTL_CORE_TB += $(PROJ_DIR)/sva/icache_assertions.sv
endif

TIMESCALE_FILE := $(PROJ_DIR)/tb/timescale.v
TB_FILE := $(PROJ_DIR)/tb/$(TOP_MODULE).sv
VCS_TIMESCALE := -timescale=1ns/1ps

ifeq ($(PROJECT),icache_plru)
  RTL_LIST := $(RTL_PKG) $(PROJ_DIR)/rtl/icache_if.sv \
	$(PROJ_DIR)/rtl/icache_plru.sv \
	$(PROJ_DIR)/rtl/icache_tag_ram.sv \
	$(PROJ_DIR)/rtl/icache_data_ram.sv
else
  RTL_LIST := $(RTL_CORE_TB)
endif

QUESTA   := $(shell command -v vlog 2>/dev/null)
VCS      := $(shell command -v vcs 2>/dev/null)
IVERILOG := $(shell command -v iverilog 2>/dev/null)

.PHONY: sim gui clean help

help:
	@echo "Targets: sim, clean"
	@echo "  PROJECT=icache_core | icache_plru"

sim: $(BUILD_DIR)
ifeq ($(QUESTA),)
ifeq ($(VCS),)
ifeq ($(IVERILOG),)
	$(error No simulator found: install Questa, VCS, or iverilog)
else
	@echo "==> iverilog ($(PROJECT))"
	cd $(BUILD_DIR) && iverilog -g2012 -o sim.vvp \
		$(RTL_LIST) $(TB_FILE) && vvp sim.vvp
endif
else
	@echo "==> VCS ($(PROJECT))"
	cd $(BUILD_DIR) && vcs -full64 -sverilog $(VCS_TIMESCALE) \
		$(TIMESCALE_FILE) $(RTL_LIST) $(TB_FILE) -top $(TOP_MODULE) -o simv && ./simv
endif
else
	@echo "==> QuestaSim ($(PROJECT))"
	cd $(BUILD_DIR) && vlog -sv $(TIMESCALE_FILE) $(RTL_LIST) $(TB_FILE) \
		&& vsim -c $(TOP_MODULE) -do "run -all; quit -f"
endif

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

clean:
	rm -rf $(PROJ_DIR)/build
