// Bus / memory microbenchmark.
//
// Measures absolute cycle cost of load-heavy and store-heavy kernels
// across the three interesting memory regions: data RAM (0x2000_0000),
// boot ROM ".rodata" (0x0000_0000), and then reports the total run
// time for context.  Results go into x28..x31 so cpu_test.v / any
// external probe can read them the same way bpu_bench.S does.
//
// Kernels (each ITER iterations):
//   x28 : RAM-load      -- repeated `lw t0, 0(s1)` to a RAM word
//   x29 : RAM-store     -- repeated `sw zero, 0(s1)` to the same word
//   x30 : ROM-load      -- repeated `lw t0, 0(s2)` from a .rodata word
//   x31 : total run cycles from entry
//
// Per-iteration instruction count is fixed at 3 (memory op + addi + bne),
// so (kernel_cycles / ITER) is a good proxy for steady-state cost of
// the memory op.  Compiler barriers (`.option push/pop` / nops) are
// unnecessary because the asm is hand-written.

    .equ ITER, 5000

    .section .text
    .globl _start
_start:
    // Park MIE so timer/external interrupts can't perturb counts.
    li      t0, (1 << 3)
    csrrc   zero, mstatus, t0

    csrr    s0, mcycle              // t_start (global)

    //---------------------------------------------------------------
    // Kernel 1: RAM load latency.
    //---------------------------------------------------------------
    la      s1, bss_buf
    sw      zero, 0(s1)             // ensure the word is valid
    li      a0, ITER
    li      a1, 0
    csrr    t0, mcycle
load_loop:
    lw      t2, 0(s1)
    addi    a1, a1, 1
    bne     a1, a0, load_loop
    csrr    t1, mcycle
    sub     x28, t1, t0

    //---------------------------------------------------------------
    // Kernel 2: RAM store latency.
    //---------------------------------------------------------------
    li      a0, ITER
    li      a1, 0
    csrr    t0, mcycle
store_loop:
    sw      zero, 0(s1)
    addi    a1, a1, 1
    bne     a1, a0, store_loop
    csrr    t1, mcycle
    sub     x29, t1, t0

    //---------------------------------------------------------------
    // Kernel 3: ROM ".rodata" load latency.
    //---------------------------------------------------------------
    la      s2, rodata_table
    li      a0, ITER
    li      a1, 0
    csrr    t0, mcycle
rom_loop:
    lw      t2, 0(s2)
    addi    a1, a1, 1
    bne     a1, a0, rom_loop
    csrr    t1, mcycle
    sub     x30, t1, t0

    csrr    t1, mcycle
    sub     x31, t1, s0

    li      x26, 1
    li      x27, 1
1:  j       1b

    //---------------------------------------------------------------
    // A few constants in .rodata for kernel 3.  Placing them explicitly
    // guarantees the ROM path is exercised (rather than the data RAM).
    //---------------------------------------------------------------
    .section .rodata
    .align 4
rodata_table:
    .word   0xdeadbeef
    .word   0xcafebabe
    .word   0x12345678
    .word   0x9abcdef0

    .section .bss
    .align 4
bss_buf:
    .skip   16
