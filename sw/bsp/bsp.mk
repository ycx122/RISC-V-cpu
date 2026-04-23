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
# The toolchain path defaults to the vendored tinyriscv GCC 8.3.0; set
# RISCV_PATH externally if you have a newer cross-compiler installed.

# --------------------------------------------------------------------
# Directory discovery (APP_DIR = caller's dir, BSP_DIR = this file's dir)
# --------------------------------------------------------------------
BSP_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
APP_DIR := $(abspath $(dir $(firstword $(MAKEFILE_LIST))))

REPO_ROOT ?= $(abspath $(BSP_DIR)/../..)

# --------------------------------------------------------------------
# Toolchain
# --------------------------------------------------------------------
RISCV_PATH ?= $(REPO_ROOT)/sw/tinyriscv/tests/toolchain/riscv64-unknown-elf-gcc-8.3.0-2020.04.0-x86_64-linux-ubuntu14

RISCV_PREFIX    ?= riscv64-unknown-elf-
RISCV_GCC       := $(RISCV_PATH)/bin/$(RISCV_PREFIX)gcc
RISCV_AS        := $(RISCV_PATH)/bin/$(RISCV_PREFIX)as
RISCV_OBJCOPY   := $(RISCV_PATH)/bin/$(RISCV_PREFIX)objcopy
RISCV_OBJDUMP   := $(RISCV_PATH)/bin/$(RISCV_PREFIX)objdump

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
RISCV_ARCH ?= rv32im
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
