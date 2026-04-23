/*
 * sw/bsp/include/bsp/gpio.h
 *
 * LED and KEY access.  These are plain 32-bit MMIO slaves wrapped in
 * axil_slave_wrapper (see rtl/soc/cpu_soc.v).  The LED shim respects
 * WSTRB[1:0] so software can pretend it is a 16-bit register; the KEY
 * shim is read-only.
 */

#ifndef BSP_GPIO_H
#define BSP_GPIO_H

#include <stdint.h>
#include "bsp/bsp.h"

#ifdef __cplusplus
extern "C" {
#endif

static inline void     led_write(uint16_t v) { mmio_write32(BSP_LED_BASE, v);    }
static inline uint16_t led_read (void)       { return (uint16_t)mmio_read32(BSP_LED_BASE); }
static inline uint8_t  key_read (void)       { return (uint8_t)mmio_read32(BSP_KEY_BASE);  }

#ifdef __cplusplus
}
#endif

#endif /* BSP_GPIO_H */
