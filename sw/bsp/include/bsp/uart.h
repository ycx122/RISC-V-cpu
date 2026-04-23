/*
 * sw/bsp/include/bsp/uart.h
 *
 * Tiny driver for rtl/peripherals/uart/cpu_uart.v, the project's legacy
 * single-register UART.  Register map (all at BSP_UART_BASE + 0):
 *
 *   write  byte            -> enqueue into TX FIFO
 *   read   uint32_t word   -> { 23'b0, rx_empty, rx_byte[7:0] }
 *
 * There is no interrupt line from this UART yet, so everything is
 * polled.  The testbench prints TX bytes live (see sim/tb/cpu_test.v),
 * which is what the smoke scripts rely on.
 *
 * This is *not* a 16550.  Once rtl/peripherals/uart/cpu_uart.v is
 * replaced by axi_uart16550 (PROCESSOR_IMPROVEMENT_PLAN.md Tier 4 #6),
 * swap out the implementation in sw/bsp/src/uart.c only.
 */

#ifndef BSP_UART_H
#define BSP_UART_H

#include <stdint.h>
#include "bsp/bsp.h"

#ifdef __cplusplus
extern "C" {
#endif

/* Blocking putc (FIFO back-pressure is opaque from C today, but the
 * hardware uart_ready handshake in cpu_uart.v stalls the CPU write on
 * FIFO full, so this call never needs software retry.)               */
void uart_putc(char c);

/* "puts" without adding a newline, matching POSIX fputs semantics.   */
void uart_puts(const char *s);

/* Non-blocking getc: returns -1 when the RX FIFO is empty, otherwise
 * the received byte as an unsigned 0..255 value.                     */
int  uart_getc_nb(void);

/* Minimal printf-like formatter.  Supported conversions:
 *   %c %s %d %u %x %X %p %%
 * Width and 0-padding are parsed but unused (we do not want a full
 * libc dependency on a 64 KB ROM).                                    */
int  uart_printf(const char *fmt, ...);

#ifdef __cplusplus
}
#endif

#endif /* BSP_UART_H */
