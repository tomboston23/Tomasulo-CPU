# test ALU instructions that ONLY use x0. 
# that way we can verify fetch without needing any decode/alu logic
.align 4
.section .text
.globl _start
    # This program will provide a simple test for
    # demonstrating OOO-ness

    # This test is NOT exhaustive
_start:

    # now start some actual tests
    li x1, 0xff00ff00
    li x2, 0x00ff00ff
    # test signed vs unsigned multiply
    mul x3, x1, x1
    mulh x3, x1, x1
    mulhu x3, x1, x1
    mulhsu x3, x1, x1
    mul x3, x1, x2
    mulh x3, x1, x2
    mulhu x3, x1, x2
    mulhsu x3, x1, x2
    mul x3, x2, x1
    mulh x3, x2, x1
    mulhu x3, x2, x1
    mulhsu x3, x2, x1
    mul x3, x2, x2
    mulh x3, x2, x2
    mulhu x3, x2, x2
    mulhsu x3, x2, x2

    li x3, 0xaaee00bb
    li x4, 0x77880022
    li x5, 0x5a
    li x6, 0xfa
    div x7, x3, x5
    divu x7, x3, x5
    rem x7, x3, x5
    remu x7, x3, x5
    div x7, x4, x5
    divu x7, x4, x5
    rem x7, x4, x5
    remu x7, x4, x5
    div x7, x3, x6
    divu x7, x3, x6
    rem x7, x3, x6
    remu x7, x3, x6
    div x7, x4, x6
    divu x7, x4, x6
    rem x7, x4, x6
    remu x7, x4, x6
    div x7, x3, x0
    div x7, x4, x0
    divu x7, x3, x0
    remu x7, x4, x0

    # test sll / srl / sra
    li x1, 1
    li x2, 31
    sll x1, x1, x2
    srl x3, x1, x2
    sra x4, x1, x2

    # test slli / srli / srai
    slli x1, x1, 31
    srli x3, x1, 31
    srai x4, x1, 31
    # make sure it only takes lower 5 bits
    li x2, 0xffffffff
    sll x1, x1, x2
    srl x3, x1, x2
    sra x4, x1, x2

    # test sltu, slt 
    li x5, 0xeeaabbcc
    li x6, 0xeeaabbcc
    li x7, 0x0eaabbcc
    slt x8, x5, x6
    slt x8, x5, x7
    sltu x8, x5, x6
    sltu x8, x5, x7

    mv x6, x8

    # test and, or, add, xor
    li x1, 0xffaaeebb
    li x2, 0x765eabcd
    add x3, x1, x2
    or  x4, x1, x2
    and x3, x3, x4
    

    slti x0, x0, -256
    
    # Program ends here - will just keep executing whatever follows
    # (likely faulting or wrapping around depending on your implementation)

.section .data
    # No data needed for this test