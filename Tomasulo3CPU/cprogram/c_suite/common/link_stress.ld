OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY {
    IMEM (rx)  : ORIGIN = 0x00000000, LENGTH = 16K
    DMEM (rwx) : ORIGIN = 0x00004000, LENGTH = 48K
}

SECTIONS {
    .text : {
        *(.text.start)
        *(.text*)
    } > IMEM

    .rodata : {
        *(.rodata*)
    } > IMEM

    . = ORIGIN(DMEM);

    .data : {
        *(.data*)
        *(.sdata*)
    } > DMEM

    .bss : {
        *(.bss*)
        *(.sbss*)
        *(COMMON)
    } > DMEM

    .tohost ALIGN(8) : {
        *(.tohost)
    } > DMEM

    . = ALIGN(16);
    _stack_top = ORIGIN(DMEM) + LENGTH(DMEM);

    /DISCARD/ : {
        *(.comment)
        *(.note*)
        *(.eh_frame*)
        *(.riscv.attributes)
    }
}
