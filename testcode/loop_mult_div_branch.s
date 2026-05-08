.align 4
.section .text
.globl _start
# Stress test for MUL / DIV / branches / loops

_start:
    ##################################################
    # Initialize registers
    ##################################################
    addi x1,  x0, 3          # x1 = 3
    addi x2,  x0, 5          # x2 = 5
    addi x3,  x0, -7         # x3 = -7
    addi x4,  x0, 11         # x4 = 11
    addi x5,  x0, 10         # x5 = 10  (Loop A counter)
    addi x6,  x0, 1          # x6 = 1   (Loop A accumulator)
    addi x7,  x0, 100        # x7 = 100 (base dividend)
    addi x8,  x0, 3          # x8 = 3   (divisor)
    addi x9,  x0, 0          # x9 = 0   (accumulate remainders)
    addi x10, x0, 8          # x10 = 8  (Loop B counter)
    addi x11, x0, 1          # x11 = 1  (Loop C counter)
    addi x12, x0, 16         # x12 = 16 (Loop C limit)

    ##################################################
    # Straight-line warm-up: various MUL/DIV forms
    ##################################################
    mul    x13, x1,  x2      # 3 * 5
    mulh   x14, x1,  x3      # high(3 * -7)
    mulhsu x15, x3,  x2      # high(-7 * 5u)
    mulhu  x16, x3,  x4      # high(-7u * 11u)

    div    x17, x1,  x3      # 3 / -7  (signed, should be 0)
    divu   x18, x7,  x2      # 100 / 5 (unsigned)
    rem    x19, x7,  x3      # 100 % -7
    remu   x20, x7,  x4      # 100 % 11u

    ##################################################
    # Loop A: repeated multiplies to grow x6
    #   for (i = 0; i < 10; i++) {
    #       x6 = x6 * x1 * x2;
    #       x21 = high(x6 * x3);
    #   }
    ##################################################
loopA:
    mul    x6,  x6,  x1      # x6 *= 3
    mul    x6,  x6,  x2      # x6 *= 5  (total x6 *= 15 per iter)
    mulh   x21, x6,  x3      # high(x6 * -7), just to exercise mulh

    addi   x5,  x5,  -1      # x5--
    bne    x5,  x0,  loopA   # repeat until x5 == 0

    ##################################################
    # Loop B: mix DIV/REM and more MUL
    #   x22 = x7;
    #   for (k = 0; k < 8; k++) {
    #       q = x22 / x8;
    #       r = x22 % x8;
    #       x9 += r;
    #       q = q * x1;
    #       x22 = q + r;
    #   }
    ##################################################
    addi   x22, x7, 0        # x22 = 100

loopB:
    div    x23, x22, x8      # q = x22 / 3
    rem    x24, x22, x8      # r = x22 % 3
    add    x9,  x9,  x24     # x9 += r

    mul    x23, x23, x1      # q *= 3
    add    x22, x23, x24     # x22 = new value (just to stir things)

    addi   x10, x10, -1      # x10--
    bne    x10, x0,  loopB   # repeat until x10 == 0

    ##################################################
    # Loop C: branch-heavy, mix MULH*, DIVU/REMU
    #
    #   for (x11 = 1; x11 < 16; x11++) {
    #       if (x11 is odd) {
    #           x26 = mulhsu(x3, x2)
    #           x27 = divu(x7, x11)
    #       } else {
    #           x28 = mulhu(x4, x2)
    #           x29 = remu(x7, x11)
    #       }
    #   }
    ##################################################
loopC:
    andi   x25, x11, 1       # x25 = x11 & 1
    beq    x25, x0, even_path   # if even, jump to even_path

odd_path:
    mulhsu x26, x3,  x2      # high(-7 * 5u)
    divu   x27, x7,  x11     # 100 / x11 (unsigned, nonzero divisor here)
    jal    x0,  joinC        # jump to join, no link

even_path:
    mulhu  x28, x4,  x2      # high(11u * 5u)
    remu   x29, x7,  x11     # 100 % x11 (unsigned)

joinC:
    addi   x11, x11, 1       # x11++
    blt    x11, x12, loopC   # loop while x11 < 16

    ##################################################
    # Tail: a few more mul/div just to finish hot
    ##################################################
    mul    x30, x6,  x7      # big multiply
    mulh   x31, x6,  x3      # high(x6 * -7)

    div    x5,  x30, x2      # x5 = x30 / 5  (signed)
    rem    x6,  x30, x2      # x6 = x30 % 5  (signed)

    ##################################################
    # Magic termination instruction
    ##################################################
    slti   x0, x0, -256      # this is the magic instruction, it ends the program

.section .data
    # No data needed
