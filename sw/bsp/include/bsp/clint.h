/*
 * sw/bsp/include/bsp/clint.h
 *
 * CLINT driver: SiFive-aligned layout as implemented in
 * rtl/peripherals/timer/clnt.v (rewritten in Tier 4 #3 of
 * PROCESSOR_IMPROVEMENT_PLAN.md).  Register offsets here MUST match that
 * RTL, and MUST NOT be confused with the older private layout that still
 * lives in sw/tinyriscv/tests/example/include/500a.h.
 *
 * Layout (base = 0x4200_0000):
 *
 *   +0x0000   msip[0]          bit 0 software interrupt pending for hart 0
 *   +0x4000   mtimecmp_lo      low  32 bits of 64-bit comparator
 *   +0x4004   mtimecmp_hi      high 32 bits of 64-bit comparator
 *   +0xBFF8   mtime_lo         low  32 bits of free-running 64-bit counter
 *   +0xBFFC   mtime_hi         high 32 bits of 64-bit counter
 *
 * Reset value of mtimecmp is 0xFFFF_FFFF_FFFF_FFFF (compare never fires).
 * mtime increments at BSP_CPU_CLK_HZ and is read-only.
 */

#ifndef BSP_CLINT_H
#define BSP_CLINT_H

#include <stdint.h>
#include "bsp/bsp.h"

#ifdef __cplusplus
extern "C" {
#endif

#define CLINT_MSIP_OFFSET       0x0000u
#define CLINT_MTIMECMP_OFFSET   0x4000u
#define CLINT_MTIME_OFFSET      0xBFF8u

#define CLINT_MSIP_ADDR         (BSP_CLINT_BASE + CLINT_MSIP_OFFSET)
#define CLINT_MTIMECMP_LO_ADDR  (BSP_CLINT_BASE + CLINT_MTIMECMP_OFFSET + 0)
#define CLINT_MTIMECMP_HI_ADDR  (BSP_CLINT_BASE + CLINT_MTIMECMP_OFFSET + 4)
#define CLINT_MTIME_LO_ADDR     (BSP_CLINT_BASE + CLINT_MTIME_OFFSET + 0)
#define CLINT_MTIME_HI_ADDR     (BSP_CLINT_BASE + CLINT_MTIME_OFFSET + 4)

/* ------------------------------------------------------------------ */
/* 64-bit atomic read of mtime.  Standard RISC-V RV32 recipe: read hi,
 * read lo, re-read hi, retry if the high word changed under us.       */
/* ------------------------------------------------------------------ */
static inline uint64_t clint_mtime(void)
{
    uint32_t hi0, lo, hi1;
    do {
        hi0 = mmio_read32(CLINT_MTIME_HI_ADDR);
        lo  = mmio_read32(CLINT_MTIME_LO_ADDR);
        hi1 = mmio_read32(CLINT_MTIME_HI_ADDR);
    } while (hi0 != hi1);
    return ((uint64_t)hi1 << 32) | lo;
}

/* ------------------------------------------------------------------ */
/* 64-bit update of mtimecmp.  Writing through in 32-bit halves has a  */
/* race where mtime can briefly exceed mtimecmp_lo and fire MTIP with  */
/* the wrong high word.  SiFive recommends: first push the high word   */
/* to 0xFFFFFFFF (effectively "never fire"), then write the low word,  */
/* then write the final high word.                                     */
/* ------------------------------------------------------------------ */
static inline void clint_set_mtimecmp(uint64_t deadline)
{
    mmio_write32(CLINT_MTIMECMP_HI_ADDR, 0xFFFFFFFFu);
    mmio_write32(CLINT_MTIMECMP_LO_ADDR, (uint32_t)(deadline & 0xFFFFFFFFu));
    mmio_write32(CLINT_MTIMECMP_HI_ADDR, (uint32_t)(deadline >> 32));
}

/* ------------------------------------------------------------------ */
/* clint_schedule_relative() -- program mtimecmp so MTIP fires after   */
/* `delta_ticks` mtime ticks relative to "right now".  Call this both  */
/* in the startup path to arm the first tick, and inside the timer IRQ */
/* handler to re-arm for the next.  Note the returned value is the new */
/* absolute mtimecmp; handlers that care about jitter can add          */
/* delta_ticks to the previous mtimecmp instead of "now" to avoid      */
/* slipping.                                                           */
/* ------------------------------------------------------------------ */
static inline uint64_t clint_schedule_relative(uint64_t delta_ticks)
{
    uint64_t deadline = clint_mtime() + delta_ticks;
    clint_set_mtimecmp(deadline);
    return deadline;
}

/* ------------------------------------------------------------------ */
/* Software interrupts.  hart 0 only on this SoC.  Writing 1 raises    */
/* MSIP; writing 0 clears it.  Bits [31:1] are WIRI.                   */
/* ------------------------------------------------------------------ */
static inline void clint_send_ipi(void)     { mmio_write32(CLINT_MSIP_ADDR, 1u); }
static inline void clint_clear_ipi(void)    { mmio_write32(CLINT_MSIP_ADDR, 0u); }
static inline uint32_t clint_msip_read(void){ return mmio_read32(CLINT_MSIP_ADDR); }

/* ------------------------------------------------------------------ */
/* Convenience: ticks per microsecond / millisecond at BSP_CPU_CLK_HZ. */
/* Computed at compile time; cast helps silence -Wshift-overflow when  */
/* BSP_CPU_CLK_HZ is redefined in user code.                           */
/* ------------------------------------------------------------------ */
#define CLINT_US_TO_TICKS(us)   ((uint64_t)(us) * (BSP_CPU_CLK_HZ / 1000000u))
#define CLINT_MS_TO_TICKS(ms)   ((uint64_t)(ms) * (BSP_CPU_CLK_HZ / 1000u))

#ifdef __cplusplus
}
#endif

#endif /* BSP_CLINT_H */
