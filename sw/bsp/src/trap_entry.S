/*
 * sw/bsp/src/trap_entry.S
 *
 * Low-level M-mode trap entry.  Builds a bsp_trap_frame on the current
 * stack, calls bsp_trap_dispatch(&frame) in C, then restores the frame
 * and `mret`s.  The frame layout MUST match `struct bsp_trap_frame` in
 * sw/bsp/include/bsp/trap.h:
 *
 *   offset  0*4 .. 31*4   x[0]..x[31]   (x[0] is padding)
 *   offset     32*4       mepc
 *   offset     33*4       mcause
 *   offset     34*4       mtval
 *   offset     35*4       mstatus
 *
 * Total size = 36 * 4 = 144 bytes; rounded up to 16-byte align for the
 * RISC-V C calling convention and psABI stack alignment.
 *
 * This entry assumes the interrupted context's stack is valid and has
 * enough headroom (the default stack is 16 KB; frames cost 144 bytes).
 * For small-stack RTOS tasks that is still well under a guard band.
 *
 * mstatus.MIE is already 0 on entry (hardware clears it as part of the
 * trap), and MPIE holds the previous MIE; `mret` restores it.  We do
 * NOT re-enable interrupts inside the handler by default.
 */

    .section .text.trap
    .align 4
    .globl  bsp_trap_entry
    .type   bsp_trap_entry, @function

#define FRAME_SIZE        (36*4 + 8)      /* 144 B + pad to 16-byte align */
#define OFF_X(i)          ((i) * 4)
#define OFF_MEPC          (32 * 4)
#define OFF_MCAUSE        (33 * 4)
#define OFF_MTVAL         (34 * 4)
#define OFF_MSTATUS       (35 * 4)

bsp_trap_entry:
    addi    sp, sp, -FRAME_SIZE

    /* x0 slot left as-is (reads as zero). */
    sw      x1,  OFF_X(1)(sp)
    sw      x2,  OFF_X(2)(sp)            /* original sp is sp+FRAME_SIZE */
    sw      x3,  OFF_X(3)(sp)
    sw      x4,  OFF_X(4)(sp)
    sw      x5,  OFF_X(5)(sp)
    sw      x6,  OFF_X(6)(sp)
    sw      x7,  OFF_X(7)(sp)
    sw      x8,  OFF_X(8)(sp)
    sw      x9,  OFF_X(9)(sp)
    sw      x10, OFF_X(10)(sp)
    sw      x11, OFF_X(11)(sp)
    sw      x12, OFF_X(12)(sp)
    sw      x13, OFF_X(13)(sp)
    sw      x14, OFF_X(14)(sp)
    sw      x15, OFF_X(15)(sp)
    sw      x16, OFF_X(16)(sp)
    sw      x17, OFF_X(17)(sp)
    sw      x18, OFF_X(18)(sp)
    sw      x19, OFF_X(19)(sp)
    sw      x20, OFF_X(20)(sp)
    sw      x21, OFF_X(21)(sp)
    sw      x22, OFF_X(22)(sp)
    sw      x23, OFF_X(23)(sp)
    sw      x24, OFF_X(24)(sp)
    sw      x25, OFF_X(25)(sp)
    sw      x26, OFF_X(26)(sp)
    sw      x27, OFF_X(27)(sp)
    sw      x28, OFF_X(28)(sp)
    sw      x29, OFF_X(29)(sp)
    sw      x30, OFF_X(30)(sp)
    sw      x31, OFF_X(31)(sp)

    /* Fix up the saved x2 to reflect the pre-trap sp (sp+FRAME_SIZE). */
    addi    t0, sp, FRAME_SIZE
    sw      t0, OFF_X(2)(sp)

    /* Snapshot the trap CSRs so the C handler can read them directly. */
    csrr    t0, mepc
    sw      t0, OFF_MEPC(sp)
    csrr    t0, mcause
    sw      t0, OFF_MCAUSE(sp)
    csrr    t0, mtval
    sw      t0, OFF_MTVAL(sp)
    csrr    t0, mstatus
    sw      t0, OFF_MSTATUS(sp)

    /* Pass &frame as the first argument. */
    mv      a0, sp
    call    bsp_trap_dispatch

    /* Handlers may rewrite frame.mepc (e.g. to skip past an ecall).   */
    lw      t0, OFF_MEPC(sp)
    csrw    mepc, t0
    lw      t0, OFF_MSTATUS(sp)
    csrw    mstatus, t0

    lw      x1,  OFF_X(1)(sp)
    /* x2 (sp) is NOT reloaded from the frame: we want it to point at
     * sp+FRAME_SIZE after the matching `addi sp, sp, +FRAME_SIZE` at
     * the bottom.  Reloading the stored sp here would just undo the
     * save sequence.                                                  */
    lw      x3,  OFF_X(3)(sp)
    lw      x4,  OFF_X(4)(sp)
    lw      x5,  OFF_X(5)(sp)
    lw      x6,  OFF_X(6)(sp)
    lw      x7,  OFF_X(7)(sp)
    lw      x8,  OFF_X(8)(sp)
    lw      x9,  OFF_X(9)(sp)
    lw      x10, OFF_X(10)(sp)
    lw      x11, OFF_X(11)(sp)
    lw      x12, OFF_X(12)(sp)
    lw      x13, OFF_X(13)(sp)
    lw      x14, OFF_X(14)(sp)
    lw      x15, OFF_X(15)(sp)
    lw      x16, OFF_X(16)(sp)
    lw      x17, OFF_X(17)(sp)
    lw      x18, OFF_X(18)(sp)
    lw      x19, OFF_X(19)(sp)
    lw      x20, OFF_X(20)(sp)
    lw      x21, OFF_X(21)(sp)
    lw      x22, OFF_X(22)(sp)
    lw      x23, OFF_X(23)(sp)
    lw      x24, OFF_X(24)(sp)
    lw      x25, OFF_X(25)(sp)
    lw      x26, OFF_X(26)(sp)
    lw      x27, OFF_X(27)(sp)
    lw      x28, OFF_X(28)(sp)
    lw      x29, OFF_X(29)(sp)
    lw      x30, OFF_X(30)(sp)
    lw      x31, OFF_X(31)(sp)

    addi    sp, sp, FRAME_SIZE
    mret

    .size   bsp_trap_entry, . - bsp_trap_entry
