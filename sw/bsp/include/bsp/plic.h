/*
 * sw/bsp/include/bsp/plic.h
 *
 * PLIC driver: SiFive-aligned layout as implemented in
 * rtl/peripherals/plic/plic.v (added in Tier 4 #3 of
 * PROCESSOR_IMPROVEMENT_PLAN.md).  Single M-mode context, 8 sources,
 * 3-bit priority.
 *
 * Layout (base = 0x4400_0000):
 *
 *   +0x0000_0004..+0x0000_001C   priority[1..7]          (3 bits each)
 *   +0x0000_1000                 pending[31:0]           (read-only)
 *   +0x0000_2000                 enable[31:0]            (context 0)
 *   +0x0020_0000                 threshold               (context 0)
 *   +0x0020_0004                 claim / complete        (context 0)
 *
 * Source 0 is reserved.  Priority 0 means "never delivered".  Claim
 * reads return the current winning IRQ id and clear its pending bit;
 * writing the same id back (complete) releases the edge gateway so a
 * still-asserted source can latch another interrupt on its next edge.
 */

#ifndef BSP_PLIC_H
#define BSP_PLIC_H

#include <stdint.h>
#include "bsp/bsp.h"

#ifdef __cplusplus
extern "C" {
#endif

#define PLIC_PRIO_BASE       (BSP_PLIC_BASE + 0x00000000u)
#define PLIC_PENDING_ADDR    (BSP_PLIC_BASE + 0x00001000u)
#define PLIC_ENABLE_ADDR     (BSP_PLIC_BASE + 0x00002000u)
#define PLIC_THRESHOLD_ADDR  (BSP_PLIC_BASE + 0x00200000u)
#define PLIC_CLAIM_ADDR      (BSP_PLIC_BASE + 0x00200004u)

#define PLIC_MAX_PRIORITY    7u   /* 3-bit field, 0 disables */

/* ------------------------------------------------------------------ */
/* Per-source priority.  irq ∈ [1, 7]; irq==0 is reserved by spec.    */
/* ------------------------------------------------------------------ */
static inline void plic_set_priority(uint32_t irq, uint32_t prio)
{
    mmio_write32(PLIC_PRIO_BASE + irq * 4u, prio & 0x7u);
}

/* ------------------------------------------------------------------ */
/* Enable / disable a single source for the only context.             */
/* ------------------------------------------------------------------ */
static inline void plic_enable(uint32_t irq)
{
    uint32_t cur = mmio_read32(PLIC_ENABLE_ADDR);
    mmio_write32(PLIC_ENABLE_ADDR, cur | (1u << irq));
}

static inline void plic_disable(uint32_t irq)
{
    uint32_t cur = mmio_read32(PLIC_ENABLE_ADDR);
    mmio_write32(PLIC_ENABLE_ADDR, cur & ~(1u << irq));
}

/* ------------------------------------------------------------------ */
/* Threshold.  Only sources with priority strictly greater than the   */
/* threshold are delivered via MEIP.  threshold=0 lets every enabled   */
/* source through provided its priority is nonzero.                    */
/* ------------------------------------------------------------------ */
static inline void plic_set_threshold(uint32_t threshold)
{
    mmio_write32(PLIC_THRESHOLD_ADDR, threshold & 0x7u);
}

/* ------------------------------------------------------------------ */
/* Claim / complete.  Standard PLIC contract:                         */
/*   id = plic_claim();                                                */
/*   if (id) { ... handle ... ; plic_complete(id); }                   */
/* A claim of 0 means "no pending enabled source for this context",   */
/* in which case complete is not required.                            */
/* ------------------------------------------------------------------ */
static inline uint32_t plic_claim(void)
{
    return mmio_read32(PLIC_CLAIM_ADDR);
}

static inline void plic_complete(uint32_t irq)
{
    mmio_write32(PLIC_CLAIM_ADDR, irq);
}

static inline uint32_t plic_pending(void)
{
    return mmio_read32(PLIC_PENDING_ADDR);
}

#ifdef __cplusplus
}
#endif

#endif /* BSP_PLIC_H */
