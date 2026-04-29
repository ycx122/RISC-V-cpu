# sw/bsp/bsp.mk
#
# Shared Make fragment for bare-metal programs that want the BSP.
#
# Usage (from sw/programs/<your_app>/Makefile):
#
#   APP_NAME   := os_demo
#   APP_CSRCS  := main.c sched.c
#   APP_ASRCS  := ctx.S
#   APP_CFLAGS := -O2 -Wall
#   include $(dir $(lastword $(MAKEFILE_LIST)))/../../bsp/bsp.mk
#
# The fragment emits:
#   $(APP_NAME)           ELF
#   $(APP_NAME).bin       raw binary (for QSPI flashing)
#   $(APP_NAME).hex       Verilog hex for +IROM=<file>
#   $(APP_NAME).dump      objdump -D (optional, for debugging)
#
# It expects APP_DIR = $(dir $(firstword $(MAKEFILE_LIST))) and BSP_DIR
# = the directory containing this fragment; both are discovered below
# so client Makefiles do not need to set them manually.
#
# Toolchain selection (see "Toolchain" section below):
#   1. If RISCV_PATH is set explicitly, it is used as-is.
#   2. Otherwise, prefer riscv64-unknown-elf-gcc on $(PATH) (e.g. apt's
#      gcc-riscv64-unknown-elf 13.2 on noble/jammy-backports).
#   3. As a last resort, fall back to the vendored 8.3.0 toolchain that
#      ships with tinyriscv.

# --------------------------------------------------------------------
# Directory discovery (APP_DIR = caller's dir, BSP_DIR = this file's dir)
# --------------------------------------------------------------------
BSP_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
APP_DIR := $(abspath $(dir $(firstword $(MAKEFILE_LIST))))

REPO_ROOT ?= $(abspath $(BSP_DIR)/../..)

# --------------------------------------------------------------------
# Toolchain (shared detection: PATH -> vendored fallback)
# --------------------------------------------------------------------
include $(BSP_DIR)/../toolchain/riscv_toolchain.mk

# --------------------------------------------------------------------
# BSP sources (everything under sw/bsp/src/)
# --------------------------------------------------------------------
BSP_ASRCS := \
    $(BSP_DIR)/src/start.S \
    $(BSP_DIR)/src/trap_entry.S

BSP_CSRCS := \
    $(BSP_DIR)/src/trap.c \
    $(BSP_DIR)/src/uart.c

BSP_LDS   ?= $(BSP_DIR)/ld/default.lds

# --------------------------------------------------------------------
# Toolchain flags
# --------------------------------------------------------------------
# Some BSP assembly files (start.S, trap_entry.S) use CSR / fence.i
# instructions. Binutils >= 2.38 (shipped with GCC >= 12) requires the
# `zicsr` / `zifencei` z-extensions to be listed explicitly in -march;
# older toolchains -- including the vendored 8.3.0 (binutils 2.32) --
# reject that spelling. Probe the resolved toolchain once and pick the
# right default. Callers can still override RISCV_ARCH from the command
# line.
ifeq ($(origin RISCV_ARCH),undefined)
  _RISCV_ZICSR_OK := $(shell $(RISCV_GCC) -march=rv32im_zicsr_zifencei -mabi=ilp32 -x c -c -o /dev/null - </dev/null 2>/dev/null && echo yes)
  ifeq ($(_RISCV_ZICSR_OK),yes)
    RISCV_ARCH := rv32im_zicsr_zifencei
  else
    RISCV_ARCH := rv32im
  endif
endif
RISCV_ABI  ?= ilp32

ARCH_FLAGS := -march=$(RISCV_ARCH) -mabi=$(RISCV_ABI) -mcmodel=medlow

# -nostdlib  -- we don't want newlib's crt0 / _init hooks
# -ffreestanding -- no assumed hosted environment (no malloc, etc.)
# -fno-builtin   -- so uart_printf isn't replaced by printf
# -Wl,--gc-sections to drop unused BSP code when the app doesn't use it.
CFLAGS_COMMON := $(ARCH_FLAGS) \
                 -ffreestanding -fno-builtin -fno-common \
                 -ffunction-sections -fdata-sections \
                 -Wall -Wextra -Werror=implicit-function-declaration \
                 -I$(BSP_DIR)/include

LDFLAGS_COMMON := $(ARCH_FLAGS) \
                  -nostdlib -nostartfiles \
                  -T$(BSP_LDS) \
                  -Wl,--gc-sections -Wl,--check-sections \
                  -Wl,-Map,$(APP_NAME).map

# Caller can add more
CFLAGS  += $(CFLAGS_COMMON) $(APP_CFLAGS)
LDFLAGS += $(LDFLAGS_COMMON) $(APP_LDFLAGS)

# --------------------------------------------------------------------
# Object file bookkeeping
# --------------------------------------------------------------------
CSRCS := $(BSP_CSRCS) $(addprefix $(APP_DIR)/,$(APP_CSRCS))
ASRCS := $(BSP_ASRCS) $(addprefix $(APP_DIR)/,$(APP_ASRCS))

BUILD_DIR ?= $(APP_DIR)/build

OBJS :=
OBJS += $(patsubst $(APP_DIR)/%.c,$(BUILD_DIR)/app_%.o,$(filter $(APP_DIR)/%,$(addprefix $(APP_DIR)/,$(APP_CSRCS))))
OBJS += $(patsubst $(APP_DIR)/%.S,$(BUILD_DIR)/app_%.o,$(filter $(APP_DIR)/%,$(addprefix $(APP_DIR)/,$(APP_ASRCS))))
OBJS += $(patsubst $(BSP_DIR)/src/%.c,$(BUILD_DIR)/bsp_%.o,$(BSP_CSRCS))
OBJS += $(patsubst $(BSP_DIR)/src/%.S,$(BUILD_DIR)/bsp_%.o,$(BSP_ASRCS))

# --------------------------------------------------------------------
# Targets
# --------------------------------------------------------------------
.PHONY: all clean
all: $(APP_NAME) $(APP_NAME).bin $(APP_NAME).hex $(APP_NAME).dump

$(BUILD_DIR):
	@mkdir -p $@

$(BUILD_DIR)/bsp_%.o: $(BSP_DIR)/src/%.c | $(BUILD_DIR)
	$(RISCV_GCC) $(CFLAGS) -c -o $@ $<

$(BUILD_DIR)/bsp_%.o: $(BSP_DIR)/src/%.S | $(BUILD_DIR)
	$(RISCV_GCC) $(CFLAGS) -c -o $@ $<

$(BUILD_DIR)/app_%.o: $(APP_DIR)/%.c | $(BUILD_DIR)
	$(RISCV_GCC) $(CFLAGS) -c -o $@ $<

$(BUILD_DIR)/app_%.o: $(APP_DIR)/%.S | $(BUILD_DIR)
	$(RISCV_GCC) $(CFLAGS) -c -o $@ $<

$(APP_NAME): $(OBJS) $(BSP_LDS)
	$(RISCV_GCC) $(LDFLAGS) $(OBJS) -o $@

$(APP_NAME).bin: $(APP_NAME)
	$(RISCV_OBJCOPY) -O binary $< $@

$(APP_NAME).hex: $(APP_NAME)
	$(RISCV_OBJCOPY) -O verilog $< $@

$(APP_NAME).dump: $(APP_NAME)
	$(RISCV_OBJDUMP) --disassemble-all -S $< > $@

clean:
	rm -rf $(BUILD_DIR)
	rm -f $(APP_NAME) $(APP_NAME).bin $(APP_NAME).hex $(APP_NAME).dump $(APP_NAME).map
