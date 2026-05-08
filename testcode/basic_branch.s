.align 4
.section .text
.globl _start
    # This program will provide a simple test for
    # verifying memory path correctness

_start:
    li x1, 500
    and x2, x2, x0
    
    loop:
        bge x2, x1, done
        addi x2, x2, 1
        j loop
    # Fence with a harmless ALU op
    done:
        slti    x0, x0, -256

.section .data
    # No data needed