/*
 * sw/bsp/src/trap.c
 *
 * M-mode trap dispatcher.  The asm-side entry (sw/bsp/src/trap_entry.S)
 * saves all GPRs + mepc/mcause/mtval/mstatus into a bsp_trap_frame on
 * the current stack, then calls bsp_trap_dispatch(&frame).  We decode
 * mcause here and fan out to per-source handlers.  On return, the asm
 * entry restores the frame and `mret`s -- including the updated mepc
 * if the handler rewrote f->mepc (needed for ecall/illegal skip).
 */

#include <stddef.h>
#include <stdint.h>
#include "bsp/bsp.h"
#include "bsp/clint.h"
#include "bsp/csr.h"
#include "bsp/trap.h"
#include "bsp/plic.h"
#include "bsp/uart.h"

#define EXC_HANDLER_SLOTS    12    /* standard sync causes 0..11 */
#define IRQ_HANDLER_SLOTS    (BSP_IRQ_MAX + 1)

static bsp_trap_handler_t timer_handler;
static bsp_trap_handler_t soft_handler;
static bsp_trap_handler_t exc_handlers[EXC_HANDLER_SLOTS];
static bsp_irq_handler_t  irq_handlers[IRQ_HANDLER_SLOTS];

/* ------------------------------------------------------------------ */
/* Panic fallback                                                      */
/* ------------------------------------------------------------------ */
static void default_banner(const struct bsp_trap_frame *f, const char *tag)
{
    uart_puts("\n[bsp] UNHANDLED TRAP: ");
    uart_puts(tag);
    uart_printf("  mcause=0x%08x  mepc=0x%08x  mtval=0x%08x  mstatus=0x%08x\n",
                f->mcause, f->mepc, f->mtval, f->mstatus);
    for (;;) {
        /* Let the outer testbench time out rather than silently spin; the
         * UART banner above already tells the user what went wrong.     */
    }
}

static void default_exception(const struct bsp_trap_frame *f)
{
    default_banner(f, "exception");
}

static void default_timer(const struct bsp_trap_frame *f)
{
    /* If the application didn't register a timer handler we still need
     * to silence MTIP to avoid a re-trap storm; push mtimecmp to the
     * "never" sentinel.                                               */
    (void)f;
    mmio_write32(CLINT_MTIMECMP_HI_ADDR, 0xFFFFFFFFu);
    mmio_write32(CLINT_MTIMECMP_LO_ADDR, 0xFFFFFFFFu);
    default_banner(f, "unhandled mti");
}

static void default_soft(const struct bsp_trap_frame *f)
{
    clint_clear_ipi();
    default_banner(f, "unhandled msi");
}

static void default_irq(uint32_t irq)
{
    uart_printf("\n[bsp] UNHANDLED PLIC IRQ %u\n", irq);
    for (;;) {}
}

/* ------------------------------------------------------------------ */
/* Registration API                                                    */
/* ------------------------------------------------------------------ */
void bsp_set_timer_handler(bsp_trap_handler_t h) { timer_handler = h; }
void bsp_set_soft_handler (bsp_trap_handler_t h) { soft_handler  = h; }

void bsp_set_exception_handler(uint32_t cause, bsp_trap_handler_t h)
{
    if (cause < EXC_HANDLER_SLOTS) exc_handlers[cause] = h;
}

void bsp_set_irq_handler(uint32_t irq, bsp_irq_handler_t h)
{
    if (irq < IRQ_HANDLER_SLOTS) irq_handlers[irq] = h;
}

/* ------------------------------------------------------------------ */
/* Global enable/disable                                               */
/* ------------------------------------------------------------------ */
void bsp_irq_enable(void)  { csr_set(mstatus, MSTATUS_MIE); }
void bsp_irq_disable(void) { csr_clear(mstatus, MSTATUS_MIE); }

void bsp_enable_timer_interrupt(void)    { csr_set(mie, MIE_MTIE); }
void bsp_enable_external_interrupt(void) { csr_set(mie, MIE_MEIE); }
void bsp_enable_software_interrupt(void) { csr_set(mie, MIE_MSIE); }

/* ------------------------------------------------------------------ */
/* Dispatcher.  Called once per trap from trap_entry.S.                */
/* ------------------------------------------------------------------ */
void bsp_trap_dispatch(struct bsp_trap_frame *f)
{
    uint32_t mcause = f->mcause;

    if (mcause & MCAUSE_INTERRUPT_BIT) {
        uint32_t code = mcause & MCAUSE_CODE_MASK;
        switch (code) {
        case MCAUSE_INT_MTI:
            (timer_handler ? timer_handler : default_timer)(f);
            break;
        case MCAUSE_INT_MSI:
            (soft_handler ? soft_handler : default_soft)(f);
            break;
        case MCAUSE_INT_MEI: {
            /* PLIC claim/complete pair.  A claim of 0 means the glitch
             * already retracted itself; we still must return cleanly.  */
            uint32_t irq = plic_claim();
            if (irq) {
                if (irq < IRQ_HANDLER_SLOTS && irq_handlers[irq])
                    irq_handlers[irq](irq);
                else
                    default_irq(irq);
                plic_complete(irq);
            }
            break;
        }
        default:
            default_banner(f, "unknown interrupt cause");
            break;
        }
    } else {
        uint32_t code = mcause & MCAUSE_CODE_MASK;
        bsp_trap_handler_t h =
            (code < EXC_HANDLER_SLOTS) ? exc_handlers[code] : NULL;
        (h ? h : default_exception)(f);
    }
}

/* ------------------------------------------------------------------ */
/* One-time BSP bring-up.  Called from main() before the application   */
/* starts installing handlers.                                          */
/* ------------------------------------------------------------------ */
void bsp_init(void)
{
    /* mtvec -- direct mode (no vectoring).  Must be 4-byte aligned,   */
    /* which GCC guarantees for a function symbol.                      */
    csr_write(mtvec, (uint32_t)(uintptr_t)bsp_trap_entry);

    /* Make sure we start with a known mstatus baseline: MPP=M (so      */
    /* mret stays in M-mode), MIE=0 (application opts in later).        */
    csr_write(mstatus, MSTATUS_MPP);

    /* Silence any stale interrupt enables left over from a previous    */
    /* boot (e.g. warm reset via UART downloader).                      */
    csr_write(mie, 0);

    /* Drain any pending PLIC claim so we don't trip the default_irq    */
    /* fallback on first enable.                                         */
    uint32_t irq = plic_claim();
    if (irq) plic_complete(irq);

    /* Push mtimecmp to "never" so MTIP starts inactive.                */
    mmio_write32(CLINT_MTIMECMP_HI_ADDR, 0xFFFFFFFFu);
    mmio_write32(CLINT_MTIMECMP_LO_ADDR, 0xFFFFFFFFu);

    /* Clear any software interrupt left over.                          */
    clint_clear_ipi();
}
