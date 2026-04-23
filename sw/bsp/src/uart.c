/*
 * sw/bsp/src/uart.c
 *
 * Driver for rtl/peripherals/uart/cpu_uart.v.  See sw/bsp/include/bsp/uart.h
 * for the register model.
 */

#include <stdarg.h>
#include <stdint.h>
#include "bsp/uart.h"

#define UART_DATA_REG       (BSP_UART_BASE + 0)
#define UART_RX_EMPTY_BIT   (1u << 8)

void uart_putc(char c)
{
    mmio_write32(UART_DATA_REG, (uint8_t)c);
}

void uart_puts(const char *s)
{
    while (*s) {
        uart_putc(*s++);
    }
}

int uart_getc_nb(void)
{
    uint32_t v = mmio_read32(UART_DATA_REG);
    if (v & UART_RX_EMPTY_BIT) {
        return -1;
    }
    return (int)(v & 0xffu);
}

/* ------------------------------------------------------------------ */
/* Minimal printf.  This is not meant to be feature-complete; it exists
 * so the OS demo (and anything else living in a 64 KB ROM) doesn't
 * have to link against the GCC printf.  Newlib's printf pulls in ~15 KB
 * of code on its own, and we need room for the kernel + scheduler.    */
/* ------------------------------------------------------------------ */

static void put_uint(uint32_t val, uint32_t base, int upper_case, int pad_width, char pad_char)
{
    static const char digits_lower[] = "0123456789abcdef";
    static const char digits_upper[] = "0123456789ABCDEF";
    const char *digits = upper_case ? digits_upper : digits_lower;

    /* 32 bits in base 2 is 32 digits + terminator; base 10 is at most
     * 10 digits.  Use 33 to cover every sensible case.                */
    char buf[33];
    int i = 0;

    if (val == 0) {
        buf[i++] = '0';
    } else {
        while (val != 0 && i < 32) {
            buf[i++] = digits[val % base];
            val /= base;
        }
    }

    for (; i < pad_width; i++) {
        buf[i] = pad_char;
    }

    while (i-- > 0) {
        uart_putc(buf[i]);
    }
}

static void put_int(int32_t val, int pad_width, char pad_char)
{
    if (val < 0) {
        uart_putc('-');
        /* -INT32_MIN overflows a signed 32-bit; cast unsigned first. */
        put_uint((uint32_t)(-(int64_t)val), 10, 0, pad_width, pad_char);
    } else {
        put_uint((uint32_t)val, 10, 0, pad_width, pad_char);
    }
}

int uart_printf(const char *fmt, ...)
{
    va_list ap;
    va_start(ap, fmt);

    int pad_width;
    char pad_char;

    for (const char *p = fmt; *p; p++) {
        if (*p != '%') {
            uart_putc(*p);
            continue;
        }

        p++;
        pad_width = 0;
        pad_char  = ' ';

        /* Parse the (intentionally tiny) flag/width syntax:
         *   '0' -> pad with '0', then digits
         *   digits -> zero-extended minimum field width            */
        if (*p == '0') {
            pad_char = '0';
            p++;
        }
        while (*p >= '0' && *p <= '9') {
            pad_width = pad_width * 10 + (*p - '0');
            p++;
        }

        switch (*p) {
        case '\0':
            goto done;
        case '%':
            uart_putc('%');
            break;
        case 'c':
            uart_putc((char)va_arg(ap, int));
            break;
        case 's': {
            const char *s = va_arg(ap, const char *);
            if (!s) s = "(null)";
            uart_puts(s);
            break;
        }
        case 'd':
        case 'i':
            put_int(va_arg(ap, int32_t), pad_width, pad_char);
            break;
        case 'u':
            put_uint(va_arg(ap, uint32_t), 10, 0, pad_width, pad_char);
            break;
        case 'x':
            put_uint(va_arg(ap, uint32_t), 16, 0, pad_width, pad_char);
            break;
        case 'X':
            put_uint(va_arg(ap, uint32_t), 16, 1, pad_width, pad_char);
            break;
        case 'p':
            uart_puts("0x");
            put_uint((uint32_t)(uintptr_t)va_arg(ap, void *), 16, 0, 8, '0');
            break;
        default:
            /* Unknown spec: print it verbatim so bugs surface.      */
            uart_putc('%');
            uart_putc(*p);
            break;
        }
    }

done:
    va_end(ap);
    return 0;
}
