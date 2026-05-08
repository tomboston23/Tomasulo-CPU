    .align 4
    .section .text
    .globl _start

# Medium loop / branch / mul/div stress test
# All loops have at most 100 iterations.

_start:
########################################################
# Init registers
########################################################
    addi x1,  x0, 0      # x1 = i (outer loop 1)
    addi x2,  x0, 50     # x2 = limit for loop 1 (50 iterations max)

    addi x3,  x0, 0      # x3 = j (inner loop 1)
    addi x4,  x0, 10     # x4 = limit for inner loop (10 iterations max)

    addi x5,  x0, 1      # x5 = accumulator A
    addi x6,  x0, 2      # x6 = accumulator B
    addi x7,  x0, 3      # x7 = accumulator C

    addi x8,  x0, 10     # x8 = loop2 limit (10 iterations)
    addi x9,  x0, 0      # x9 = k (loop 2 counter)

    addi x10, x0, 1      # x10 = constant 1
    addi x11, x0, 2      # x11 = constant 2
    addi x12, x0, 3      # x12 = constant 3

########################################################
# Loop 1: nested loop but bounded:
#   outer: 0..49 (50 iters)
#   inner: 0..9  (10 iters)
# Total inner iterations: 500
########################################################

outer1:
    bge  x1, x2, outer1_done   # if i >= 50, exit outer1

    # Reset inner loop counter j = 0
    addi x3, x0, 0

inner1:
    bge  x3, x4, inner1_done   # if j >= 10, exit inner1

    # Some arithmetic in the inner loop:
    # x5 += i + j
    add  x13, x1, x3           # x13 = i + j
    add  x5,  x5, x13          # x5 += (i + j)

    # x6 = x6 * 2 + 1  (using mul + add)
    mul  x6, x6, x11           # x6 *= 2
    add  x6, x6, x10           # x6 = x6 + 1

    # conditional: if j is odd, tweak x7
    andi x14, x3, 1            # x14 = j & 1
    beq  x14, x0, inner1_even

inner1_odd:
    add  x7, x7, x1            # if odd: x7 += i
    jal  x0, inner1_next

inner1_even:
    sub  x7, x7, x1            # if even: x7 -= i

inner1_next:
    addi x3, x3, 1             # j++
    jal  x0, inner1

inner1_done:
    addi x1, x1, 1             # i++
    jal  x0, outer1

outer1_done:

########################################################
# Loop 2: small loop with mul/div
#   k from 0 to 9 (10 iterations)
########################################################

loop2:
    bge  x9, x8, loop2_done    # if k >= 10, exit loop2

    # x15 = k + 5
    addi x15, x9, 5

    # Avoid divide-by-zero: divisor is always >= 1
    addi x16, x9, 1            # x16 = k + 1

    # x17 = (x15 * 3)
    mul  x17, x15, x12         # *3

    # x18 = x17 / x16 (signed)
    div  x18, x17, x16

    # x19 = x17 % x16 (signed rem)
    rem  x19, x17, x16

    # Accumulate results to keep them “live”
    add  x5,  x5,  x18
    add  x6,  x6,  x19

    addi x9, x9, 1             # k++
    jal  x0, loop2

loop2_done:

########################################################
# Loop 3: simple up-counting loop
# runs 0..99 (100 iterations exactly)
########################################################

    addi x20, x0, 0            # x20 = counter
    addi x21, x0, 100          # limit = 100

loop3:
    bge  x20, x21, loop3_done  # if counter >= 100, exit

    # if x20 is multiple of 4, add something to x7
    andi x22, x20, 3           # x22 = x20 & 3
    bne  x22, x0, loop3_notmult4

loop3_mult4:
    add  x7, x7, x20
    jal  x0, loop3_next

loop3_notmult4:
    sub  x7, x7, x20

loop3_next:
    addi x20, x20, 1
    jal  x0, loop3

loop3_done:

########################################################
# Final few ops to stir results
########################################################

    # combine x5,x6,x7 into x23 via some mul/add/div
    add  x23, x5, x6
    mul  x23, x23, x7
    addi x24, x0, 7
    div  x23, x23, x24     # safe, divisor = 7
    rem  x25, x23, x11     # remainder mod 2

########################################################
# Magic termination instruction
########################################################
    slti x0, x0, -256      # this is the magic instruction, it ends the program

.section .data
    # No data needed
