.section .text.start
.globl _start
_start:
    li sp, 0x400
    call main
1:
    j 1b
