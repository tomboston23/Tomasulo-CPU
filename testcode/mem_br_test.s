# test basic memory operations using x0 and x1
# verifies memory fetch/store and basic load-store path
.align 4
.section .text
.globl _start
    # This program will provide a simple test for
    # verifying memory path correctness

_start:
    # x1 = base pointer = 0xAAAAA000 (valid region)
    lui     x1, 0xAAAAA
    lh      x13, 14(x1)          # sign-extend half from overlap region
    lb      x12, 3(x1)           # expect 0x78 (positive)
    add x1, x0, x1


    # # Small immediate test values
    addi    x2, x0, 0x12         # 0x12
    addi    x3, x0, 0x34         # 0x34
    addi    x4, x0, 0x78         # 0x78
    addi    x5, x0, -1           # 0xFFFFFFFF (tests sign extension)
    addi    x6, x0, 0x7F         # 0x0000007F
    addi    x7, x0, 0x80         # 0x00000080 (tests signed LB)

    li x10, 0
    li x11, 6
    li x12, 8
loop:
    add x14, x1, x10
    # sb  x6, 0(x14)
    addi x10, x10, 1
    bge x10, x11, halt
    j loop

    # Fence with a harmless ALU op
halt:
    slti    x0, x0, -256

.section .data
    # No data needed