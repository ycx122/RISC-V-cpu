/*
 * sw/bsp/include/bsp/trap.h
 *
 * Trap handling contract between sw/bsp/src/trap_entry.S (asm glue
 * that saves/restores registers) and application code.  The asm entry
 * builds a `trap_frame` on the current stack, calls `bsp_trap_dispatch`
 * with (mcause, mepc, &frame), then `mret`s.
 *
 * Applications register:
 *   - bsp_set_irq_handler(irq, handler)   for PLIC sources (mcause=MEI)
 *   - bsp_set_timer_handler(handler)       for mcause=MTI
 *   - bsp_set_soft_handler(handler)        for mcause=MSI
 *   - bsp_set_exception_handler(cause, h)  for synchronous exceptions
 *
 * All handlers run with MIE=0 (trap entry clears it).  Re-enabling
 * interrupts inside a handler is allowed for nested interrupts, but
 * the default BSP does NOT do this to keep the trap model simple.
 *
 * If no handler is registered for a given cause, the BSP default
 * installs a banner dumper that prints {mcause, mepc, mtval} over the
 * UART and infinite-loops -- useful when something unexpected fires
 * inside a new port.
 */

#ifndef BSP_TRAP_H
#define BSP_TRAP_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Layout matches sw/bsp/src/trap_entry.S.  Do NOT reorder without also
 * updating the asm save/restore macros.  x0 is not saved (always zero);
 * x1..x31 are stored at offsets 1*4..31*4; the frame has 32*4 = 128
 * bytes of GPR state.                                                  */
struct bsp_trap_frame {
    uint32_t x[32];      /* x[0] unused / zero-initialised */
    uint32_t mepc;
    uint32_t mcause;
    uint32_t mtval;
    uint32_t mstatus;
};

typedef void (*bsp_trap_handler_t)(const struct bsp_trap_frame *f);
typedef void (*bsp_irq_handler_t)(uint32_t irq);

/* ------------------------------------------------------------------ */
/* Registration API                                                   */
/* ------------------------------------------------------------------ */
void bsp_set_timer_handler(bsp_trap_handler_t h);
void bsp_set_soft_handler (bsp_trap_handler_t h);
void bsp_set_exception_handler(uint32_t cause, bsp_trap_handler_t h);
void bsp_set_irq_handler(uint32_t irq, bsp_irq_handler_t h);

/* ------------------------------------------------------------------ */
/* Global interrupt enable / disable (manipulates mstatus.MIE only).  */
/* Individual sources still need mie.MTIE / mie.MSIE / mie.MEIE and   */
/* their peripheral-side enable bits.                                 */
/* ------------------------------------------------------------------ */
void bsp_irq_enable (void);
void bsp_irq_disable(void);

/* ------------------------------------------------------------------ */
/* Low-level mie helpers, for clarity at the call site.                */
/* ------------------------------------------------------------------ */
void bsp_enable_timer_interrupt(void);
void bsp_enable_external_interrupt(void);
void bsp_enable_software_interrupt(void);

/* ------------------------------------------------------------------ */
/* Implemented in trap_entry.S -- address goes into mtvec.  Declared  */
/* here mostly so C code can see the symbol without a forward decl.   */
/* ------------------------------------------------------------------ */
extern void bsp_trap_entry(void);

/* ------------------------------------------------------------------ */
/* Called from trap_entry.S with the fully-built frame.  Application  */
/* code never calls this directly; it exists as a public prototype so */
/* that the asm glue can reference a C symbol with external linkage.  */
/* ------------------------------------------------------------------ */
void bsp_trap_dispatch(struct bsp_trap_frame *f);

#ifdef __cplusplus
}
#endif

#endif /* BSP_TRAP_H */
