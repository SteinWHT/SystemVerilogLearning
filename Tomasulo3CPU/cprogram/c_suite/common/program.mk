SUITE_ROOT := $(abspath $(CURDIR)/..)
COMMON_DIR := $(SUITE_ROOT)/common
ARCH_TEST_DIR := $(abspath $(SUITE_ROOT)/../../arch_test)

ARCH ?= rv64im
ABI ?= lp64

PYTHON ?= python

CC := riscv-none-elf-gcc
OBJDUMP := riscv-none-elf-objdump
SIZE := riscv-none-elf-size

CFLAGS := -march=$(ARCH) -mabi=$(ABI) -nostdlib -nostartfiles -ffreestanding \
          -fno-builtin -O1 -Wall -Wextra -Wno-unused-parameter
LDFLAGS := -T $(COMMON_DIR)/link.ld -nostdlib

PROGRAM ?= unknown
BUILD_DIR := $(SUITE_ROOT)/build/$(PROGRAM)

ELF := $(BUILD_DIR)/$(PROGRAM).elf
DUMP := $(BUILD_DIR)/$(PROGRAM).dump

.PHONY: all clean hex size

all: $(ELF) $(DUMP) hex size

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(ELF): $(BUILD_DIR) $(COMMON_DIR)/start.S $(COMMON_DIR)/runtime.c main.c $(COMMON_DIR)/link.ld
	$(CC) $(CFLAGS) $(LDFLAGS) -o $@ $(COMMON_DIR)/start.S $(COMMON_DIR)/runtime.c main.c

$(DUMP): $(ELF)
	$(OBJDUMP) -d -M no-aliases $< > $@

hex: $(ELF)
	$(PYTHON) "$(ARCH_TEST_DIR)/elf_to_hex.py" "$<" --output-dir "$(BUILD_DIR)"

size: $(ELF)
	$(SIZE) $<

clean:
	rm -rf "$(BUILD_DIR)"
