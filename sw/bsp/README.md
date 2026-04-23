# RISC-V CPU BSP

Board-support package for bare-metal programs running on the SoC defined
in `rtl/soc/cpu_soc.v`.  Replaces the legacy `sw/tinyriscv/tests/example/`
BSP, which is hard-coded to the old private CLNT register layout and
therefore no longer works against the current SoC.

## Layout

```
sw/bsp/
├── bsp.mk              # shared Make fragment (toolchain + link rules)
├── include/bsp/        # headers (user-facing API)
│   ├── bsp.h           # base addresses, bsp_init()
│   ├── csr.h           # csr_read / csr_write macros + mstatus / mcause bits
│   ├── clint.h         # CLINT driver (SiFive layout)
│   ├── plic.h          # PLIC driver (SiFive layout)
│   ├── uart.h          # tiny UART driver + printf
│   ├── gpio.h          # LED / KEY
│   └── trap.h          # trap frame + handler registration
├── src/
│   ├── start.S         # crt0 (.data copy + .bss clear + call main)
│   ├── trap_entry.S    # asm trap entry, builds bsp_trap_frame
│   ├── trap.c          # C trap dispatcher + handler registry
│   └── uart.c          # UART driver + printf
└── ld/default.lds      # default linker script (64 KB ROM, 128 KB RAM)
```

## Writing a BSP-based program

```
# sw/programs/my_app/Makefile
APP_NAME  := my_app
APP_CSRCS := main.c
APP_CFLAGS := -O2
include ../../bsp/bsp.mk
```

`main.c`:

```c
#include <stdint.h>
#include "bsp/bsp.h"
#include "bsp/clint.h"
#include "bsp/plic.h"
#include "bsp/uart.h"
#include "bsp/trap.h"

static void tick(const struct bsp_trap_frame *f) {
    (void)f;
    static uint32_t ticks;
    uart_printf("tick %u\n", ++ticks);
    clint_schedule_relative(CLINT_MS_TO_TICKS(100));
}

int main(void) {
    bsp_init();
    bsp_set_timer_handler(tick);
    clint_schedule_relative(CLINT_MS_TO_TICKS(100));
    bsp_enable_timer_interrupt();
    bsp_irq_enable();
    for (;;) { __asm__ volatile("wfi"); }
    return 0;
}
```

Then:

```
$ make            # build my_app, my_app.bin, my_app.hex, my_app.dump
$ make clean      # clean
```

## Hardware expectations

The BSP only assumes the M-mode baseline that is already shipped:

* RV32IM
* SiFive-aligned CLINT at `0x4200_0000`
* SiFive-aligned PLIC at `0x4400_0000`
* UART at `0x4300_0000` (private protocol; swap `src/uart.c` when the
  SoC upgrades to 16550)
* 64 KB boot ROM at `0x0000_0000`, 128 KB data RAM at `0x2000_0000`.

When the SoC moves to larger RAM / DDR or adds PMP / S-mode, update
`bsp.h`, `ld/default.lds`, and `src/trap.c` in lock-step.
