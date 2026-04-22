// Minimal machine-mode trap smoke test.
//
// Exercises:
//   - CSR read/write semantics: csrrw / csrrs / csrrc on mscratch
//   - Synchronous exception round-trip: ecall  -> mcause == 11, mepc == ecall PC
//   - Synchronous exception round-trip: ebreak -> mcause ==  3, mepc == ebreak PC
//
// Protocol follows cpu_test.v: x26 == 1 (done), x27 == 1 (pass),
//                              x3 is the current testnum on failure.

    .section .text
    .globl _start
_start:
    // Disable external M-mode interrupt so the testbench's e_inter=1
    // cannot asynchronously divert the stream. Sync traps still work.
    li      t0, (1 << 3)          // mstatus.MIE
    csrrc   zero, mstatus, t0

    // Point mtvec (direct mode) at our handler.
    la      t0, trap_handler
    csrw    mtvec, t0

    //--------------------------------------------------------------
    // Test 1: basic csrrw round-trip on mscratch
    //--------------------------------------------------------------
    li      x3, 1
    li      t0, 0xdeadbeef
    csrw    mscratch, t0
    csrr    t1, mscratch
    bne     t0, t1, fail

    //--------------------------------------------------------------
    // Test 2: csrrs sets bits, returns old value
    //--------------------------------------------------------------
    li      x3, 2
    li      t0, 0x0000ffff
    csrw    mscratch, t0
    li      t1, 0xffff0000
    csrrs   t2, mscratch, t1     // rd = old = 0x0000ffff
    bne     t2, t0, fail
    csrr    t2, mscratch
    li      t3, 0xffffffff
    bne     t2, t3, fail

    //--------------------------------------------------------------
    // Test 3: csrrc clears bits
    //--------------------------------------------------------------
    li      x3, 3
    li      t0, 0xffffffff
    csrw    mscratch, t0
    li      t1, 0x0000ffff
    csrrc   zero, mscratch, t1
    csrr    t2, mscratch
    li      t3, 0xffff0000
    bne     t2, t3, fail

    //--------------------------------------------------------------
    // Test 4: ecall round-trip
    //   Expect: mcause == 11, mepc == &ecall_site, mret returns to the
    //           instruction immediately after ecall (handler does mepc+=4).
    //--------------------------------------------------------------
    li      x3, 4
    li      x28, 0                 // handler flag
ecall_site:
    ecall
    nop
    nop
    li      t0, 0xcafe
    bne     x28, t0, fail

    //--------------------------------------------------------------
    // Test 5: ebreak round-trip (same, but mcause == 3)
    //--------------------------------------------------------------
    li      x3, 5
    li      x28, 0
ebreak_site:
    ebreak
    nop
    nop
    li      t0, 0xbeef
    bne     x28, t0, fail

    //--------------------------------------------------------------
    // Test 7: IllegalInstruction round-trip
    //   Expect: mcause == 2, mepc == &illegal_site (faulting PC), and
    //           the instruction did NOT commit (wb_en was forced off in
    //           id.v default branch).  Handler bumps mepc by 4 to skip
    //           the faulting word and returns into the trailing nops.
    //
    //   `.word 0x0000007F` has inst[1:0]==2'b11 (RV32I width) but
    //   inst[6:2]==5'b11111 which is reserved / >=48-bit in base ISA,
    //   so id.v hits `default` and raises `illegal`.
    //--------------------------------------------------------------
    li      x3, 7
    li      x28, 0
illegal_site:
    .word   0x0000007F
    nop
    nop
    li      t0, 0xdeed
    bne     x28, t0, fail

    //--------------------------------------------------------------
    // Test 6: async interrupt round-trip
    //
    //   The testbench drives `e_inter` low (asserting the external
    //   interrupt source) when run with +EINT_AT.  Until now we kept
    //   mstatus.MIE = 0 to block async traps.  Here we reopen the gate
    //   inside a tight nop loop; level-sensitive MEIP fires as soon as
    //   MIE is written and we land in trap_handler with mcause's top
    //   bit set.  The handler must:
    //     * check mcause == 0x8000000B (MEI -- highest-priority),
    //     * check mepc points *inside* [int_loop, int_loop_end) -- i.e.
    //       the PC of the next not-yet-committed instruction, NOT the
    //       already-retired one in WB (this is exactly what the pc_next
    //       plumbing in cpu_jh.v / csr_reg.v is supposed to deliver),
    //     * permanently mask MIE by clearing both mstatus.MIE and
    //       mstatus.MPIE so mret does not drop us straight back in
    //       (MEIP stays high until the SoC's source is cleared),
    //     * redirect mret to int_loop_end,
    //     * stash 0xabcd into x28 so the mainline can confirm the
    //       round-trip actually happened.
    //--------------------------------------------------------------
    li      x3, 6
    li      x28, 0
    li      t0, (1 << 3)
    csrrs   zero, mstatus, t0
int_loop:
    nop
    nop
    nop
    nop
    j       int_loop
int_loop_end:
    li      t0, 0xabcd
    bne     x28, t0, fail

    //--------------------------------------------------------------
    // Test 8: WFI immediate wake when mip & mie != 0 (MIE==0)
    //
    //   Test 6 left mstatus.MIE=0 and mstatus.MPIE=0 (permanently
    //   masked) but did *not* touch mie.MEIE (still enabled from
    //   reset) and the testbench keeps MEIP asserted (e_inter=0).
    //   Privileged spec 3.3.3 says WFI must resume whenever
    //   (mip & mie) != 0 regardless of mstatus.MIE: when MIE=0 the
    //   interrupt stays pending but the hart wakes and falls through
    //   to the next instruction without trapping.
    //
    //   If wfi_halt logic in csr_reg.v/cpu_jh.v were broken, the
    //   pipeline would be stuck here forever and the watchdog would
    //   fire instead of TEST_PASS.
    //--------------------------------------------------------------
    li      x3, 8
    li      x28, 0
wfi_site:
    wfi
    li      x28, 0xf00d            // must execute after wake
    li      t0, 0xf00d
    bne     x28, t0, fail

    //--------------------------------------------------------------
    // All tests passed
    //--------------------------------------------------------------
pass:
    li      x26, 1
    li      x27, 1
1:  j       1b

fail:
    li      x26, 1
    li      x27, 0
2:  j       2b


//===============================================================
// Trap handler (direct mode, entered with mtvec[1:0] = 00)
//===============================================================
    .align 2
trap_handler:
    csrr    s0, mcause
    csrr    s1, mepc

    // Async interrupts set mcause[31]=1; branch early.
    bltz    s0, handle_int

    li      t6, 11
    beq     s0, t6, handle_ecall

    li      t6, 3
    beq     s0, t6, handle_ebreak

    li      t6, 2
    beq     s0, t6, handle_illegal

    j       fail                    // unexpected cause

handle_illegal:
    la      t6, illegal_site
    bne     s1, t6, fail            // mepc must point at the faulting word
    li      x28, 0xdeed
    j       trap_return

handle_ecall:
    la      t6, ecall_site
    bne     s1, t6, fail            // mepc must point at ecall itself
    li      x28, 0xcafe
    j       trap_return

handle_ebreak:
    la      t6, ebreak_site
    bne     s1, t6, fail
    li      x28, 0xbeef
    j       trap_return

handle_int:
    // With the level-sensitive CLINT/PLIC model, the testbench asserts
    // MEIP (via e_inter=0), so mcause reports MEI (code 11 + int bit).
    li      t6, 0x8000000B
    bne     s0, t6, fail

    // mepc must land somewhere inside the int_loop body, i.e. point at
    // a not-yet-committed instruction.  The old mepc semantics wrote
    // the PC of the already-retired WB instruction, which would have
    // caused mret to re-execute it; that is the bug this subtest
    // exists to catch.
    la      t5, int_loop
    la      t6, int_loop_end
    bltu    s1, t5, fail
    bgeu    s1, t6, fail

    // Permanently mask MIE (and MPIE, so mret cannot re-enable MIE).
    li      t0, (1 << 3) | (1 << 7)
    csrrc   zero, mstatus, t0

    // Exit the loop: redirect mret to int_loop_end.
    csrw    mepc, t6

    li      x28, 0xabcd
    mret

trap_return:
    addi    s1, s1, 4               // skip the ecall/ebreak
    csrw    mepc, s1
    mret
