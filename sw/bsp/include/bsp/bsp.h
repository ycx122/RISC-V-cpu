/*
 * sw/bsp/include/bsp/bsp.h
 *
 * Board-support header for the RISC-V CPU SoC defined in
 * rtl/soc/cpu_soc.v.  The memory map lives here rather than scattered
 * across drivers so a change in cpu_soc.v only needs to be mirrored in
 * one place.
 *
 * Address map (see rtl/bus/axil_interconnect.v):
 *
 *   0x0000_0000 - 0x0FFF_FFFF   Boot ROM      (rxai!w)   64 KB populated
 *   0x2000_0000 - 0x2FFF_FFFF   Data RAM      (wa!rix)  128 KB populated
 *   0x4000_0000 - 0x40FF_FFFF   GPIO.LED
 *   0x4100_0000 - 0x41FF_FFFF   GPIO.KEY
 *   0x4200_0000 - 0x42FF_FFFF   CLINT (SiFive layout)
 *   0x4300_0000 - 0x43FF_FFFF   UART (tinyriscv private)
 *   0x4400_0000 - 0x44FF_FFFF   PLIC  (SiFive layout)
 *
 * Out-of-window accesses raise DECERR (see PROCESSOR_IMPROVEMENT_PLAN.md
 * Tier A #3), which the CPU turns into mcause=5 (load access fault) or
 * mcause=7 (store access fault) with mtval=offending address.
 */

#ifndef BSP_BSP_H
#define BSP_BSP_H

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

/* ------------------------------------------------------------------ */
/* Base addresses                                                      */
/* ------------------------------------------------------------------ */
#define BSP_ROM_BASE     0x00000000u
#define BSP_ROM_SIZE     0x00010000u   /* 64 KB usable */
#define BSP_RAM_BASE     0x20000000u
#define BSP_RAM_SIZE     0x00020000u   /* 128 KB usable */

#define BSP_LED_BASE     0x40000000u
#define BSP_KEY_BASE     0x41000000u
#define BSP_CLINT_BASE   0x42000000u
#define BSP_UART_BASE    0x43000000u
#define BSP_PLIC_BASE    0x44000000u

/* ------------------------------------------------------------------ */
/* Interrupt source numbers (PLIC gateway indices)                     */
/* ------------------------------------------------------------------ */
/* source 0 is reserved by spec */
#define BSP_IRQ_EXTERNAL_PIN  1u   /* cpu_soc.v ties e_inter here */
#define BSP_IRQ_MAX           7u   /* plic.v instantiated with 8 sources */

/* ------------------------------------------------------------------ */
/* Clock (matches rtl/soc/cpu_soc.v clk_wiz_0 configuration).  The     */
/* simulation clock is the testbench's `always #10 clk = ~clk` toggle, */
/* i.e. 50 MHz.  On-board the clk_wiz_0 PLL takes the 50 MHz input and */
/* produces a 50 MHz cpu_clk (output divider = 1).  BSP code uses this */
/* to convert from microseconds into mtime ticks without touching any  */
/* runtime measurement.                                                */
/* ------------------------------------------------------------------ */
#define BSP_CPU_CLK_HZ   50000000u

/* ------------------------------------------------------------------ */
/* Small MMIO helpers.  All MMIO is strict 32-bit aligned; everything  */
/* else goes through the AXI master bridge's wstrb/byte-extract paths  */
/* and is not typically needed from C.                                 */
/* ------------------------------------------------------------------ */
static inline void     mmio_write32(uintptr_t addr, uint32_t v) {
    *(volatile uint32_t *)addr = v;
}

static inline uint32_t mmio_read32(uintptr_t addr) {
    return *(volatile uint32_t *)addr;
}

/* ------------------------------------------------------------------ */
/* bsp_init() -- call once from main() before enabling interrupts.    */
/* Sets up the UART console, programs `mtvec` to the shared asm entry */
/* point (bsp_trap_entry) and clears any pending PLIC claim state.    */
/* Does NOT enable MIE; let the caller do that after installing IRQ   */
/* handlers.                                                          */
/* ------------------------------------------------------------------ */
void bsp_init(void);

#ifdef __cplusplus
}
#endif

#endif /* BSP_BSP_H */
