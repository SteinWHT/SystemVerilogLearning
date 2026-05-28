/* Linker script for riscv-tests on Tomasulo3CPU (physical mem at 0x0). */
OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    RAM (rwx) : ORIGIN = 0x00000000, LENGTH = 64K
}

SECTIONS {
    . = 0x00000000;
    .text.init : { *(.text.init) } > RAM
    .tohost     : { *(.tohost) } > RAM
    . = ALIGN(16);
    .text       : { *(.text) *(.text.rvtest) *(.text.*) } > RAM
    . = ALIGN(8);
    .data       : { *(.data) } > RAM
    .bss        : { *(.bss) } > RAM
    _end = .;
}
