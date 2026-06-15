# DMA simulation Makefile (stub — RTL not yet implemented)
#
# Usage (once tb exists):
#   make sim PROJECT=dma_axi_master

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

PROJECT   ?= dma_axi_master
PROJ_DIR  := $(shell pwd)
BUILD_DIR := $(PROJ_DIR)/build/$(PROJECT)
TOP_MODULE := $(PROJECT)_tb

.PHONY: sim clean help

help:
	@echo "DMA RTL is not yet implemented."
	@echo "See doc/DMA_PLAN.md for the build-out order."

sim:
	@echo "ERROR: $(TOP_MODULE) not found. Implement RTL per doc/DMA_PLAN.md first." >&2
	@exit 1

clean:
	rm -rf $(PROJ_DIR)/build
