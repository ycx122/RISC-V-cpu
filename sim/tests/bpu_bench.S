// Branch-predictor microbenchmark.
//
// Measures cycles taken by representative branch-heavy kernels and
// stashes the counts in x28-x31 so a waveform / testbench hook can
// read them out.  Protocol follows cpu_test.v: x26 == 1 (done),
// x27 == 1 (pass), x3 holds a failing testnum on abort.
//
// Kernels:
//   x28 : "tight backward loop" -- addi + bne -- 10 000 iterations.
//         Without prediction every taken bne eats one bubble
//         (3 cycles/iter steady state).  With a correctly trained
//         2-bit BHT hit every iteration collapses to 2 cycles/iter.
//
//   x29 : "call/return stream" -- jal ra, f ; ret -- 5 000 pairs.
//         Each pair is 2 taken control transfers.  Without prediction
//         that's ~4 cycles per pair; with BTB for JAL + RAS for ret
//         it drops to ~2 cycles per pair.
//
//   x30 : "forward branch (NT bias)" -- beq (never taken) -- 10 000 iters.
//         Branch is always not-taken; no penalty with or without BP,
//         but verifies the NT path is still correct when the BHT
//         starts weakly-NT and never flips.
//
//   x31 : total cycles from entry to end of final kernel (for context).
//
// IMPORTANT: x28..x31 alias t3..t6 in the RISC-V ABI, so kernel bodies
//            must not use t3..t6 as scratch — we'd clobber each other's
//            results.  Only t0/t1/t2 (and a-regs) are used as scratch
//            below; the final kernel totals are moved into x28..x31 with
//            a single sub instruction at the end.
//
// Run standalone:
//   riscv64-unknown-elf-gcc -march=rv32im -mabi=ilp32 -nostdlib -nostartfiles \
//       -T sw/tinyriscv/tests/example/d.lds sim/tests/bpu_bench.S -o bpu_bench.elf
//   riscv64-unknown-elf-objcopy -O verilog bpu_bench.elf bpu_bench.verilog
//   vvp -n <sim> +IROM=bpu_bench.verilog

    .section .text
    .globl _start
_start:
    // Make sure M-mode interrupts can't interfere with cycle counts.
    li      t0, (1 << 3)
    csrrc   zero, mstatus, t0

    csrr    s0, mcycle              // t_start (global)

    //---------------------------------------------------------------
    // Kernel 1: tight backward loop (10 000 iterations).
    //---------------------------------------------------------------
    li      a0, 10000
    li      a1, 0
    csrr    t0, mcycle
loop1:
    addi    a1, a1, 1
    bne     a1, a0, loop1
    csrr    t1, mcycle
    sub     x28, t1, t0

    //---------------------------------------------------------------
    // Kernel 2: call / ret stream (5 000 pairs).
    //---------------------------------------------------------------
    li      a0, 5000
    li      a1, 0
    csrr    t0, mcycle
loop2:
    jal     ra, leaf
    addi    a1, a1, 1
    bne     a1, a0, loop2
    csrr    t1, mcycle
    sub     x29, t1, t0
    j       k3

leaf:
    ret

k3:
    //---------------------------------------------------------------
    // Kernel 3: forward, never-taken branch (10 000 iterations).
    //---------------------------------------------------------------
    li      a0, 10000
    li      a1, 0
    csrr    t0, mcycle
loop3:
    addi    a1, a1, 1
    beq     a1, zero, skip_ft      // never taken -- a1 > 0 after first iter
skip_ft:
    bne     a1, a0, loop3
    csrr    t1, mcycle
    sub     x30, t1, t0

    csrr    t1, mcycle
    sub     x31, t1, s0

    // Report pass.
    li      x26, 1
    li      x27, 1
1:  j       1b
