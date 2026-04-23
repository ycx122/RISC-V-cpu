/*
 * sw/programs/os_demo/switch.S
 *
 * Coop context switcher.  Matches the layout of `struct sched_ctx`
 * from sched.h:
 *
 *   offset  0*4   ra
 *   offset  1*4   sp
 *   offset  2*4   s0
 *   offset  3*4   s1
 *   offset  4..13 s2..s11
 *
 * Caller-saved registers (the t and a families) are live across the
 * sched_switch() call only as far as the C ABI requires: the compiler
 * either keeps them in registers in each task's active function or
 * spills them to that task's own stack before the call.  So we do not
 * save or restore them here.
 *
 * void sched_switch(struct sched_ctx *prev, struct sched_ctx *next);
 *                       a0                     a1
 */

    .section .text
    .globl   sched_switch
    .type    sched_switch, @function
    .align   2

sched_switch:
    sw   ra,  0(a0)
    sw   sp,  4(a0)
    sw   s0,  8(a0)
    sw   s1, 12(a0)
    sw   s2, 16(a0)
    sw   s3, 20(a0)
    sw   s4, 24(a0)
    sw   s5, 28(a0)
    sw   s6, 32(a0)
    sw   s7, 36(a0)
    sw   s8, 40(a0)
    sw   s9, 44(a0)
    sw   s10,48(a0)
    sw   s11,52(a0)

    lw   ra,  0(a1)
    lw   sp,  4(a1)
    lw   s0,  8(a1)
    lw   s1, 12(a1)
    lw   s2, 16(a1)
    lw   s3, 20(a1)
    lw   s4, 24(a1)
    lw   s5, 28(a1)
    lw   s6, 32(a1)
    lw   s7, 36(a1)
    lw   s8, 40(a1)
    lw   s9, 44(a1)
    lw   s10,48(a1)
    lw   s11,52(a1)
    ret

    .size   sched_switch, . - sched_switch
