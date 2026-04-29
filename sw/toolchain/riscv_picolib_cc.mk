# sw/toolchain/riscv_picolib_cc.mk
#
# Optional compile-only fragment when $(RISCV_GCC) does not see libc headers
# (Ubuntu gcc-riscv64-unknown-elf is bare-metal-only). Picolibc supplies headers
# and specs so `-std`/hosted includes resolve without linking its crt.
#
# Prerequisites:
#   - Include after sw/toolchain/riscv_toolchain.mk (defines RISCV_GCC,
#     PICOLIBC_SPECS_DEFAULT).
#
# Optional before include:
#   RV_PICOLIB_PROBE_HEADER -- header to probe (default: stdio.h). Use
#     stdlib.h for sources that only pull FreeRTOS / embedded stacks.

RV_PICOLIB_PROBE_HEADER ?= stdio.h

_RISCV_HAS_HOST_HEADERS := $(shell $(RISCV_GCC) -include $(RV_PICOLIB_PROBE_HEADER) -E -x c /dev/null >/dev/null 2>&1 && echo yes)

ifneq ($(_RISCV_HAS_HOST_HEADERS),yes)
  PICOLIBC_SPECS ?= $(PICOLIBC_SPECS_DEFAULT)
  ifneq ($(wildcard $(PICOLIBC_SPECS)),)
    PICOLIBC_CC_CFLAGS += --specs=$(PICOLIBC_SPECS)
  endif
endif
