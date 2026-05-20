/* Minimal linker script for Tomasulo3CPU bare-metal programs */
/* Code starts at 0x0000, data/stack at 0x0400 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 1K
    DMEM (rwx) : ORIGIN = 0x00000400, LENGTH = 1K
}

SECTIONS {
    .text : {
        *(.text.start)
        *(.text*)
    } > IMEM

    .rodata : {
        *(.rodata*)
    } > IMEM

    .data : {
        *(.data*)
        *(.sdata*)
    } > DMEM

    .bss : {
        *(.bss*)
        *(.sbss*)
    } > DMEM

    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
        *(.riscv.attributes)
    }
}
