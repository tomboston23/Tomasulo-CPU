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
    li x13, 0xE0ab
    li x12, 0xF3
    sh      x13, 14(x1)          # sign-extend half from overlap region
    sb      x12, 3(x1)           # expect 0x78 (positive)
    add x1, x0, x1


    # # Small immediate test values
    addi    x2, x0, 0x12         # 0x12
    addi    x3, x0, 0x34         # 0x34
    addi    x4, x0, 0x78         # 0x78
    addi    x5, x0, -1           # 0xFFFFFFFF (tests sign extension)
    addi    x6, x0, 0x7F         # 0x0000007F
    addi    x7, x0, 0x80         # 0x00000080 (tests signed LB)


    sw      x2, 0(x1)            # MEM[0]  = 0x00000012
    sh      x3, 4(x1)            # MEM[4]  = 0x0034
    sb      x4, 8(x1)            # MEM[8]  = 0x78


    sw      x5, 12(x1)           # MEM[12] = 0xFFFFFFFF
    sb      x6, 12(x1)           # overwrite LSB → MEM[12] = 0xFFFFFF7F
    sh      x7, 14(x1)           # overwrite upper two bytes of the word region

    lw      x10, 0(x1)           # expect 0x00000012
    lh      x11, 4(x1)           # expect 0x0034 (positive)
    lb      x12, 8(x1)           # expect 0x78 (positive)


    lh      x13, 14(x1)          # sign-extend half from overlap region
    lb      x14, 17(x1)          # sign/zero check after mixed overwrites


    lhu     x15, 4(x1)
    lbu     x16, 8(x1)


    sw      x10, 20(x1)
    sw      x11, 24(x1)
    sw      x12, 28(x1)
    sw      x13, 32(x1)
    sw      x14, 36(x1)
    sw      x15, 40(x1)
    sw      x16, 44(x1)

    # Fence with a harmless ALU op
    slti    x0, x0, -256

.section .data
    # No data needed