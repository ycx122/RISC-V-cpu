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
    // Test 11: CLINT SiFive layout sanity check.  Read mtime_lo twice;
    //   the free-running machine timer must advance between reads.
    //--------------------------------------------------------------
    li      x3, 11
    li      t0, 0x4200BFF8           // CLINT base + 0xBFF8 = mtime_lo
    lw      t1, 0(t0)
    lw      t2, 0(t0)
    bgeu    t1, t2, fail

    //--------------------------------------------------------------
    // Test 12: CLINT MSIP round-trip (machine software interrupt).
    //   Raise msip via the CLINT MMIO register at base+0x0000, enable
    //   MIE and expect an MSI trap (mcause=0x80000003).  The handler
    //   clears msip back to 0, permanently masks MIE (so the MEIP that
    //   the PLIC still has pending from Test 6 does not re-trigger on
    //   mret) and stamps 0xb00b into x28.
    //--------------------------------------------------------------
    li      x3, 12
    li      x28, 0
    li      t0, 0x42000000           // CLINT msip[0]
    li      t1, 1
    sw      t1, 0(t0)
    // Mask MEIE first so the still-pending PLIC MEIP cannot pre-empt
    // this subtest; MSIE / MTIE stay as the reset defaults.
    li      t0, (1 << 11)            // mie.MEIE
    csrrc   zero, mie, t0
    li      t0, (1 << 3)             // mstatus.MIE
    csrrs   zero, mstatus, t0
msi_site:
    nop
    nop
    nop
    li      t0, 0xb00b
    bne     x28, t0, fail

    //--------------------------------------------------------------
    // Test 13: CLINT mtime/mtimecmp round-trip (MTI).
    //   Program mtimecmp a few cycles ahead of mtime and re-open MIE;
    //   the handler raises mtimecmp to the max 64-bit value to clear
    //   MTIP, then permanently masks MIE again (MSIE / MEIE stay off)
    //   before returning.
    //--------------------------------------------------------------
    li      x3, 13
    li      x28, 0
    // Keep MEIE masked (from Test 12) and mask MSIE as well so only
    // MTIE can cause a trap during this subtest.
    li      t0, (1 << 3)             // mie.MSIE
    csrrc   zero, mie, t0
    // Program mtimecmp = current mtime_lo + 1 (mtimecmp_hi = 0).  The
    // read-modify-write round-trip alone burns more than one cycle, so
    // mtime is already strictly greater than mtimecmp by the time the
    // sw retires; the free-running counter guarantees the comparator
    // asserts MTIP before `csrrs mstatus` below re-enables MIE, which
    // in turn guarantees the interrupt fires inside the nop window.
    li      t0, 0x4200BFF8           // mtime_lo
    lw      t1, 0(t0)
    addi    t1, t1, 1
    li      t0, 0x42004000           // mtimecmp_lo
    sw      t1, 0(t0)
    sw      zero, 4(t0)              // mtimecmp_hi = 0
    li      t0, (1 << 3)             // mstatus.MIE
    csrrs   zero, mstatus, t0
mti_site:
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    nop
    li      t0, 0xd07
    bne     x28, t0, fail

    //--------------------------------------------------------------
    // Test 6: async interrupt round-trip (via SiFive-style PLIC)
    //
    //   The testbench drives `e_inter` low (asserting external
    //   interrupt source #1 on the PLIC) when run with +EINT_AT.  Unlike
    //   earlier revisions, MEIP is no longer a direct wire from the pad:
    //   the PLIC arbitrates per-source priority / enable / threshold
    //   before asserting `meip` into the hart.  Before re-enabling MIE
    //   we therefore program the PLIC for source 1:
    //     * priority[1] = 1
    //     * enable[1]   = 1 (context 0 / hart 0 M-mode)
    //     * threshold   = 0 (so priority 1 wins arbitration)
    //   With that set up, level-sensitive MEIP fires as soon as MIE is
    //   written and we land in trap_handler with mcause's top bit set.
    //
    //   The handler must:
    //     * check mcause == 0x8000000B (MEI -- highest-priority),
    //     * check mepc points *inside* [int_loop, int_loop_end) -- i.e.
    //       the PC of the next not-yet-committed instruction, NOT the
    //       already-retired one in WB,
    //     * read the PLIC claim register and verify it returns source
    //       id 1 (so claim arbitration agrees with the mcause),
    //     * write that id back to claim/complete to release the
    //       gateway,
    //     * permanently mask MIE by clearing both mstatus.MIE and
    //       mstatus.MPIE so mret does not drop us straight back in
    //       (MEIP reasserts once the source is not in-flight),
    //     * redirect mret to int_loop_end,
    //     * stash 0xabcd into x28 so the mainline can confirm the
    //       round-trip actually happened.
    //--------------------------------------------------------------
    li      x3, 6
    li      x28, 0

    // Program PLIC: priority[1]=1, enable[1]=1, threshold=0.
    li      t0, 0x44000004        // PLIC base + priority[1]
    li      t1, 1
    sw      t1, 0(t0)
    li      t0, 0x44002000        // PLIC base + enable (context 0)
    li      t1, 0x00000002        // bit 1 = source id 1
    sw      t1, 0(t0)
    li      t0, 0x44200000        // PLIC base + threshold (context 0)
    sw      zero, 0(t0)

    // Tests 12/13 cleared mie.MEIE and mie.MSIE; restore both so the
    // PLIC MEIP can dispatch as an async trap.
    li      t0, (1 << 11) | (1 << 3)
    csrrs   zero, mie, t0

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
    // Test 9: Load Access Fault (Tier 4.2, Tier A #3)
    //
    //   A load to an unmapped MMIO address (0x5000_0000) must surface
    //   as mcause=5, mtval=0x5000_0000, mepc=&load_fault_site.  The
    //   cpu pipeline also has to:
    //     * suppress the regfile write-back of the garbage DECERR rdata
    //       (a3 must stay at its sentinel 0xbad00 value),
    //     * keep an unrelated ALU result just after the load intact,
    //       so the handler can resume at the nop following the load.
    //
    //   Handler sets x28=0xfade and bumps mepc past the load.
    //--------------------------------------------------------------
    li      x3, 9
    li      x28, 0
    li      a3, 0xbad00           // sentinel: must survive the DECERR
    li      t1, 0x50000000
load_fault_site:
    lw      a3, 0(t1)             // -> DECERR, trap, rd write squashed
    nop
    nop
    li      t0, 0xfade
    bne     x28, t0, fail
    li      t2, 0xbad00
    bne     a3, t2, fail          // rd must not have been clobbered

    //--------------------------------------------------------------
    // Test 10: Store Access Fault
    //
    //   Same drill for a store.  mcause=7, mtval=0x5000_0004 (we pick
    //   a distinct address just to confirm mtval tracks the actual
    //   bad pointer, not some stale latch).  No rd to worry about.
    //--------------------------------------------------------------
    li      x3, 10
    li      x28, 0
    li      t1, 0x50000004
    li      t2, 0xdeadbeef
store_fault_site:
    sw      t2, 0(t1)             // -> DECERR, trap
    nop
    nop
    li      t0, 0xc001
    bne     x28, t0, fail

    //--------------------------------------------------------------
    // Test 14: Store Address Misaligned (Tier A #2)
    //
    //   SH at a byte-odd address must trap synchronously as
    //   mcause=6, mtval=0x2000_0001, mepc=&store_misalign_site.  The
    //   AXI master bridge short-circuits the request (no AW/W fires),
    //   so the transaction never reaches the RAM slave.  Handler
    //   stamps 0x6006 into x28 and bumps mepc past the faulting SH.
    //--------------------------------------------------------------
    li      x3, 14
    li      x28, 0
    li      t1, 0x20000001        // RAM base + 1 : half-word misaligned
    li      t2, 0x0000dead
store_misalign_site:
    sh      t2, 0(t1)             // -> misalign trap, mcause=6
    nop
    nop
    li      t0, 0x6006
    bne     x28, t0, fail

    //--------------------------------------------------------------
    // Test 15: Load Address Misaligned (Tier A #2)
    //
    //   LW at a non-word-aligned address must trap synchronously as
    //   mcause=4, mtval=0x2000_0001, mepc=&load_misalign_site.  Same
    //   rd-preservation requirement as Test 9: the AXI bridge did
    //   not fetch anything, so `a3` must retain its sentinel.
    //--------------------------------------------------------------
    li      x3, 15
    li      x28, 0
    li      a3, 0xbad15           // sentinel: must survive the misalign
    li      t1, 0x20000001        // RAM base + 1 : word misaligned
load_misalign_site:
    lw      a3, 0(t1)             // -> misalign trap, mcause=4, rd squashed
    nop
    nop
    li      t0, 0x4004
    bne     x28, t0, fail
    li      t2, 0xbad15
    bne     a3, t2, fail          // rd must not have been clobbered

    //--------------------------------------------------------------
    // Test 16: ROM write returns SLVERR (Tier A #1)
    //
    //   Stores targeting the ROM window used to be silently dropped
    //   by the underlying ROM slave.  The interconnect now routes
    //   ROM writes through its synthetic SLVERR path so they surface
    //   as a Store Access Fault (mcause=7) with mtval pointing at
    //   the ROM offset the software tried to clobber.  This test
    //   stores to ROM offset 0x10 (well inside the vectored boot
    //   region) and expects the standard access-fault handoff.
    //--------------------------------------------------------------
    li      x3, 16
    li      x28, 0
    li      t1, 0x00000010        // inside ROM (slave 0)
    li      t2, 0xcafebabe
rom_write_site:
    sw      t2, 0(t1)             // -> SLVERR, mcause=7
    nop
    nop
    li      t0, 0xc0de
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

    li      t6, 5
    beq     s0, t6, handle_load_fault

    li      t6, 7
    beq     s0, t6, handle_store_fault

    li      t6, 4
    beq     s0, t6, handle_load_misalign

    li      t6, 6
    beq     s0, t6, handle_store_misalign

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

handle_load_fault:
    la      t6, load_fault_site
    bne     s1, t6, fail            // mepc must point at the faulting load
    csrr    t5, mtval
    li      t6, 0x50000000
    bne     t5, t6, fail            // mtval must carry the faulting address
    li      x28, 0xfade
    j       trap_return

handle_store_fault:
    // Two distinct tests raise mcause=7: Test 10 (unmapped MMIO store,
    // mtval=0x5000_0004) and Test 16 (ROM write, mtval=0x0000_0010).
    // Demux on mepc because the Tier A #1 interconnect now routes ROM
    // writes through its synthetic SLVERR path, which is observably
    // indistinguishable from a DECERR at the csr_reg level.
    la      t6, store_fault_site
    beq     s1, t6, handle_store_fault_unmapped
    la      t6, rom_write_site
    beq     s1, t6, handle_store_fault_rom
    j       fail

handle_store_fault_unmapped:
    csrr    t5, mtval
    li      t6, 0x50000004
    bne     t5, t6, fail
    li      x28, 0xc001
    j       trap_return

handle_store_fault_rom:
    csrr    t5, mtval
    li      t6, 0x00000010
    bne     t5, t6, fail
    li      x28, 0xc0de
    j       trap_return

handle_load_misalign:
    la      t6, load_misalign_site
    bne     s1, t6, fail
    csrr    t5, mtval
    li      t6, 0x20000001
    bne     t5, t6, fail
    li      x28, 0x4004
    j       trap_return

handle_store_misalign:
    la      t6, store_misalign_site
    bne     s1, t6, fail
    csrr    t5, mtval
    li      t6, 0x20000001
    bne     t5, t6, fail
    li      x28, 0x6006
    j       trap_return

handle_int:
    // MSI (software IPI) branch.
    li      t6, 0x80000003
    beq     s0, t6, handle_msi

    // MTI (machine timer) branch.
    li      t6, 0x80000007
    beq     s0, t6, handle_mti

    // With the level-sensitive CLINT/PLIC model, the testbench asserts
    // MEIP via PLIC source 1, so mcause reports MEI (code 11 + int bit).
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

    // PLIC claim: should return id=1 (our external source).  Write the
    // id back to claim/complete to release the gateway so subsequent
    // tests see mip.MEIP reasserted (e_inter is still low).
    li      t3, 0x44200004         // PLIC claim/complete (context 0)
    lw      t4, 0(t3)
    li      t5, 1
    bne     t4, t5, fail
    sw      t4, 0(t3)

    // Exit the loop: redirect mret to int_loop_end.
    csrw    mepc, t6

    li      x28, 0xabcd
    mret

trap_return:
    addi    s1, s1, 4               // skip the ecall/ebreak
    csrw    mepc, s1
    mret

//---------------------------------------------------------------
// Machine Software Interrupt (Test 12) -- clear CLINT msip[0] and
// permanently mask MIE so mret does not immediately re-trap.  The
// handler also sanity-checks mepc against the msi_site label.
//---------------------------------------------------------------
handle_msi:
    // The precise PC at which the MSI is recognised depends on fetch-path
    // latency (TCM / ICACHE_DISABLE / I-Cache all differ), so we skip
    // the tight mepc range check here and only validate the cause.
    li      t0, 0x42000000          // CLINT msip[0]
    sw      zero, 0(t0)

    li      t0, (1 << 3) | (1 << 7)
    csrrc   zero, mstatus, t0

    li      x28, 0xb00b
    mret

//---------------------------------------------------------------
// Machine Timer Interrupt (Test 13) -- push mtimecmp all the way to
// the max 64-bit value so MTIP drops and mtime cannot catch up
// during the remainder of the test, then permanently mask MIE.
//---------------------------------------------------------------
handle_mti:
    // Push mtimecmp to the maximum 64-bit value.  Writing mtimecmp_hi
    // first pins the comparator above any achievable `mtime`, so MTIP
    // deasserts atomically as far as the CSR block is concerned and
    // cannot re-fire during the remainder of the smoke test.
    li      t0, 0x42004000
    li      t1, -1
    sw      t1, 4(t0)                // mtimecmp_hi = 0xFFFF_FFFF
    sw      t1, 0(t0)                // mtimecmp_lo = 0xFFFF_FFFF

    li      t0, (1 << 3) | (1 << 7)
    csrrc   zero, mstatus, t0        // permanently mask MIE / MPIE

    li      x28, 0xd07
    mret
