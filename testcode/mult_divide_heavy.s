    .align 4
    .section .text
    .globl _start
# Big MUL/DIV/REM stress test for RISC-V M extension

_start:
    ##################################################
    # Initialize registers with a variety of values
    ##################################################
    addi    x1,  x0, 100        # +100
    addi    x2,  x0, 7          # +7
    addi    x3,  x0, -7         # -7
    addi    x4,  x0, 13         # +13
    addi    x5,  x0, -13        # -13
    addi    x6,  x0, 31         # +31
    addi    x7,  x0, -31        # -31
    addi    x8,  x0, 1          # +1
    addi    x9,  x0, -1         # -1
    addi    x10, x0, 0          # 0
    addi    x11, x0, 2
    addi    x12, x0, -2
    addi    x13, x0, 3
    addi    x14, x0, -3
    addi    x15, x0, 5
    addi    x16, x0, -5
    addi    x17, x0, 9
    addi    x18, x0, -9
    addi    x19, x0, 16
    addi    x20, x0, -16
    addi    x21, x0, 25
    addi    x22, x0, -25
    addi    x23, x0, 37
    addi    x24, x0, -37

    ##################################################
    # Block 1: Basic MUL + DIV chains
    ##################################################
    mul     x25, x1,  x2        # 100 * 7
    mul     x26, x3,  x4        # -7 * 13
    mul     x27, x5,  x6        # -13 * 31
    mul     x28, x7,  x8        # -31 * 1
    mul     x29, x19, x11       # 16 * 2
    mul     x30, x21, x13       # 25 * 3
    mul     x31, x23, x15       # 37 * 5

    div     x25, x25, x2        # ((100*7) / 7)
    div     x26, x26, x3        # ((-7*13) / -7)
    div     x27, x27, x5        # ((-13*31) / -13)
    div     x28, x28, x7        # ((-31*1) / -31)
    div     x29, x29, x11       # ((16*2) / 2)
    div     x30, x30, x13       # ((25*3) / 3)
    div     x31, x31, x15       # ((37*5) / 5)

    ##################################################
    # Block 2: MULH / MULHU / MULHSU tests
    ##################################################
    mulh    x25, x1,  x3        # 100 * -7 (high)
    mulh    x26, x2,  x5        # 7 * -13
    mulh    x27, x4,  x7        # 13 * -31
    mulh    x28, x6,  x8        # 31 * 1
    mulh    x29, x9,  x5        # -1 * -13
    mulh    x30, x17, x19       # 9 * 16
    mulh    x31, x18, x20       # -9 * -16

    mulhu   x25, x1,  x2        # 100u * 7u
    mulhu   x26, x6,  x4        # 31u * 13u
    mulhu   x27, x19, x11       # 16u * 2u
    mulhu   x28, x21, x13       # 25u * 3u
    mulhu   x29, x23, x15       # 37u * 5u
    mulhu   x30, x17, x2        # 9u * 7u
    mulhu   x31, x19, x6        # 16u * 31u

    mulhsu  x25, x3,  x2        # -7  * 7u
    mulhsu  x26, x5,  x4        # -13 * 13u
    mulhsu  x27, x7,  x6        # -31 * 31u
    mulhsu  x28, x18, x11       # -9  * 2u
    mulhsu  x29, x20, x13       # -16 * 3u
    mulhsu  x30, x22, x15       # -25 * 5u
    mulhsu  x31, x24, x17       # -37 * 9u

    ##################################################
    # Block 3: Unsigned DIVU + REMU
    ##################################################
    divu    x25, x1,  x2        # 100u / 7u
    divu    x26, x1,  x4        # 100u / 13u
    divu    x27, x6,  x4        # 31u / 13u
    divu    x28, x19, x11       # 16u / 2u
    divu    x29, x17, x15       # 9u / 5u
    divu    x30, x19, x17       # 16u / 9u
    divu    x31, x4,  x11       # 13u / 2u

    remu    x25, x1,  x2        # 100u % 7u
    remu    x26, x1,  x4        # 100u % 13u
    remu    x27, x6,  x4        # 31u % 13u
    remu    x28, x19, x11       # 16u % 2u
    remu    x29, x17, x15       # 9u % 5u
    remu    x30, x19, x17       # 16u % 9u
    remu    x31, x4,  x11       # 13u % 2u

    ##################################################
    # Block 4: Signed DIV + REM
    ##################################################
    div     x25, x1,  x2        # 100 / 7
    div     x26, x1,  x3        # 100 / -7
    div     x27, x3,  x2        # -7 / 7
    div     x28, x5,  x4        # -13 / 13
    div     x29, x6,  x4        # 31 / 13
    div     x30, x7,  x4        # -31 / 13
    div     x31, x19, x11       # 16 / 2

    rem     x25, x1,  x2        # 100 % 7
    rem     x26, x1,  x3        # 100 % -7
    rem     x27, x3,  x2        # -7 % 7
    rem     x28, x5,  x4        # -13 % 13
    rem     x29, x6,  x4        # 31 % 13
    rem     x30, x7,  x4        # -31 % 13
    rem     x31, x19, x11       # 16 % 2

    ##################################################
    # Block 5: Divide-by-zero behavior
    ##################################################
    # RISC-V spec: DIV/DIVU by zero => quotient = -1 (all ones),
    # REM/REMU by zero => remainder = dividend
    div     x25, x1,  x10       # 100 / 0
    div     x26, x3,  x10       # -7 / 0
    divu    x27, x1,  x10       # 100u / 0
    divu    x28, x19, x10       # 16u / 0

    rem     x29, x1,  x10       # 100 % 0
    rem     x30, x3,  x10       # -7 % 0
    remu    x31, x1,  x10       # 100u % 0
    remu    x21, x19, x10       # 16u % 0

    ##################################################
    # Block 6: Long chained MUL+DIV+REM sequences
    ##################################################
    # Start with some combined products
    mul     x22, x1,  x4        # 100 * 13
    mul     x23, x3,  x5        # -7 * -13
    mul     x24, x6,  x7        # 31 * -31
    mul     x25, x19, x17       # 16 * 9
    mul     x26, x21, x23       # 25 * 37
    mul     x27, x22, x11       # (100*13) * 2
    mul     x28, x23, x13       # (-7*-13) * 3
    mul     x29, x24, x15       # (31*-31) * 5
    mul     x30, x25, x17       # (16*9) * 9
    mul     x31, x26, x19       # (25*37) * 16

    # Now divide and take remainders in chains
    div     x22, x22, x2
    rem     x23, x23, x4
    divu    x24, x24, x11
    remu    x25, x25, x15

    div     x26, x26, x3
    rem     x27, x27, x6
    divu    x28, x28, x2
    remu    x29, x29, x11

    div     x30, x30, x17
    rem     x31, x31, x19

    # Second stage of chain
    mul     x22, x22, x23
    mul     x23, x24, x25
    mul     x24, x26, x27
    mul     x25, x28, x29
    mul     x26, x30, x31

    div     x27, x22, x11
    divu    x28, x23, x15
    rem     x29, x24, x17
    remu    x30, x25, x19
    div     x31, x26, x2

    ##################################################
    # Block 7: Alternating MUL/MULH/MULHU/MULHSU with DIV/REM
    ##################################################
    mul     x22, x1,  x2
    mulh    x23, x22, x3
    mulhu   x24, x23, x4
    mulhsu  x25, x24, x11

    div     x26, x25, x5
    rem     x27, x26, x6

    mul     x28, x27, x7
    mulh    x29, x28, x8
    mulhu   x30, x29, x11
    mulhsu  x31, x30, x13

    divu    x22, x31, x15
    remu    x23, x22, x17

    mul     x24, x23, x19
    mulh    x25, x24, x21
    mulhu   x26, x25, x23
    mulhsu  x27, x26, x2

    div     x28, x27, x3
    rem     x29, x28, x4
    divu    x30, x29, x11
    remu    x31, x30, x6

    ##################################################
    # Block 8: Self-multiply and self-divide edge-ish cases
    ##################################################
    mul     x1,  x1,  x1
    mul     x2,  x2,  x2
    mul     x3,  x3,  x3
    mul     x4,  x4,  x4
    mul     x5,  x5,  x5
    mul     x6,  x6,  x6
    mul     x7,  x7,  x7
    mul     x8,  x8,  x8

    div     x9,  x1,  x8       # large-ish / 1
    div     x10, x3,  x9       # -7^3 / -1^something
    rem     x11, x4,  x2
    remu    x12, x6,  x5
    divu    x13, x7,  x1
    remu    x14, x2,  x11

    ##################################################
    # Magic termination instruction
    ##################################################
    slti    x0, x0, -256       # magic instruction to end the program

    .section .data
    # No data needed