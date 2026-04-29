# sw/programs/freertos_demo/Makefile
#
# Standalone build: bypasses sw/bsp/bsp.mk on purpose because the BSP
# fragment always pulls in trap_entry.S + trap.c, and this app needs
# FreeRTOS's own trap handler (freertos_risc_v_trap_handler) at mtvec
# instead.  We cherry-pick start.S (crt0) + uart.c from the BSP.
#
# Produces:
#   freertos_demo           ELF
#   freertos_demo.bin       raw binary
#   freertos_demo.hex       Verilog hex for +IROM=<file>
#   freertos_demo.dump      objdump for debugging
#   freertos_demo.map       linker map

APP_NAME := freertos_demo

# --------------------------------------------------------------------
# Paths
# --------------------------------------------------------------------
APP_DIR   := $(abspath $(dir $(firstword $(MAKEFILE_LIST))))
REPO_ROOT := $(abspath $(APP_DIR)/../../..)
BSP_DIR   := $(REPO_ROOT)/sw/bsp
RTOS_DIR  := $(REPO_ROOT)/sw/FreeRTOS-Kernel
PORT_DIR  := $(RTOS_DIR)/portable/GCC/RISC-V
CHIP_DIR  := $(PORT_DIR)/chip_specific_extensions/RV32I_CLINT_no_extensions
HEAP_DIR  := $(RTOS_DIR)/portable/MemMang

BUILD_DIR := $(APP_DIR)/build

# --------------------------------------------------------------------
# Toolchain (shared: PATH -> vendored fallback)
# --------------------------------------------------------------------
include $(REPO_ROOT)/sw/toolchain/riscv_toolchain.mk

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

# Apt gcc-riscv64-unknown-elf has no bundled libc headers; picolibc supplies them.
RV_PICOLIB_PROBE_HEADER := stdlib.h
include $(REPO_ROOT)/sw/toolchain/riscv_picolib_cc.mk

# --------------------------------------------------------------------
# Include search paths
#   -I <app>   : FreeRTOSConfig.h
#   -I <kernel>: FreeRTOS.h, task.h, queue.h, ...
#   -I <port>  : portmacro.h
#   -I <chip>  : freertos_risc_v_chip_specific_extensions.h (asm-only,
#               but safe to include everywhere)
#   -I <bsp>   : bsp/bsp.h, bsp/uart.h, bsp/csr.h, ...
# --------------------------------------------------------------------
INCLUDES := \
    -I$(APP_DIR) \
    -I$(RTOS_DIR)/include \
    -I$(PORT_DIR) \
    -I$(CHIP_DIR) \
    -I$(BSP_DIR)/include

# --------------------------------------------------------------------
# Flags
# --------------------------------------------------------------------
CFLAGS := $(ARCH_FLAGS) $(PICOLIBC_CC_CFLAGS) \
          -Os -g \
          -ffreestanding -fno-builtin -fno-common \
          -ffunction-sections -fdata-sections \
          -Wall -Wextra \
          -Wno-unused-parameter -Wno-unused-function \
          -Werror=implicit-function-declaration \
          $(INCLUDES)

# portASM.S has `.align 8` and uses include paths from the ASM side.
ASFLAGS := $(CFLAGS)

LDFLAGS := $(ARCH_FLAGS) \
           -nostdlib -nostartfiles \
           -T$(BSP_DIR)/ld/default.lds \
           -Wl,--gc-sections -Wl,--check-sections \
           -Wl,-Map,$(APP_NAME).map

# libgcc supplies __mulsi3 / __divsi3 / __udivsi3 helpers that GCC may
# emit even when -mhw-div is available (e.g. 64-bit mults inside the
# FreeRTOS tick math).  Keeping the path is cheap insurance.
LIBS := -lgcc

# --------------------------------------------------------------------
# Sources
# --------------------------------------------------------------------
# BSP bits we reuse.  Note we deliberately skip trap_entry.S and
# trap.c -- FreeRTOS installs its own trap handler at mtvec.
BSP_ASRCS := $(BSP_DIR)/src/start.S
BSP_CSRCS := $(BSP_DIR)/src/uart.c

# FreeRTOS kernel core.  croutine/event_groups/timers/stream_buffer
# are not used by this demo; dropping them shrinks the ROM by ~6 KB.
RTOS_CSRCS := \
    $(RTOS_DIR)/tasks.c \
    $(RTOS_DIR)/queue.c \
    $(RTOS_DIR)/list.c \
    $(PORT_DIR)/port.c \
    $(HEAP_DIR)/heap_4.c

RTOS_ASRCS := \
    $(PORT_DIR)/portASM.S

# Application sources
APP_CSRCS := main.c newlib_stubs.c
APP_ASRCS :=

# --------------------------------------------------------------------
# Object list
# --------------------------------------------------------------------
# Flatten to build/<flavor>_<basename>.o so two different source dirs
# can have the same base filename without colliding.
obj_of = $(BUILD_DIR)/$(1)_$(notdir $(basename $(2))).o

BSP_OBJS  := $(foreach s,$(BSP_CSRCS),$(call obj_of,bsp,$(s))) \
             $(foreach s,$(BSP_ASRCS),$(call obj_of,bsp,$(s)))
RTOS_OBJS := $(foreach s,$(RTOS_CSRCS),$(call obj_of,rtos,$(s))) \
             $(foreach s,$(RTOS_ASRCS),$(call obj_of,rtos,$(s)))
APP_OBJS  := $(foreach s,$(APP_CSRCS),$(call obj_of,app,$(s))) \
             $(foreach s,$(APP_ASRCS),$(call obj_of,app,$(s)))

OBJS := $(BSP_OBJS) $(RTOS_OBJS) $(APP_OBJS)

# --------------------------------------------------------------------
# Build rules (one static rule per source directory so the prefix
# derivation above actually works).
# --------------------------------------------------------------------
.PHONY: all clean
all: $(APP_NAME) $(APP_NAME).bin $(APP_NAME).hex $(APP_NAME).dump

$(BUILD_DIR):
	@mkdir -p $@

# BSP
$(BUILD_DIR)/bsp_%.o: $(BSP_DIR)/src/%.c | $(BUILD_DIR)
	$(RISCV_GCC) $(CFLAGS) -c -o $@ $<
$(BUILD_DIR)/bsp_%.o: $(BSP_DIR)/src/%.S | $(BUILD_DIR)
	$(RISCV_GCC) $(ASFLAGS) -c -o $@ $<

# Application
$(BUILD_DIR)/app_%.o: $(APP_DIR)/%.c | $(BUILD_DIR)
	$(RISCV_GCC) $(CFLAGS) -c -o $@ $<
$(BUILD_DIR)/app_%.o: $(APP_DIR)/%.S | $(BUILD_DIR)
	$(RISCV_GCC) $(ASFLAGS) -c -o $@ $<

# FreeRTOS kernel
$(BUILD_DIR)/rtos_tasks.o: $(RTOS_DIR)/tasks.c | $(BUILD_DIR)
	$(RISCV_GCC) $(CFLAGS) -c -o $@ $<
$(BUILD_DIR)/rtos_queue.o: $(RTOS_DIR)/queue.c | $(BUILD_DIR)
	$(RISCV_GCC) $(CFLAGS) -c -o $@ $<
$(BUILD_DIR)/rtos_list.o: $(RTOS_DIR)/list.c | $(BUILD_DIR)
	$(RISCV_GCC) $(CFLAGS) -c -o $@ $<
$(BUILD_DIR)/rtos_port.o: $(PORT_DIR)/port.c | $(BUILD_DIR)
	$(RISCV_GCC) $(CFLAGS) -c -o $@ $<
$(BUILD_DIR)/rtos_heap_4.o: $(HEAP_DIR)/heap_4.c | $(BUILD_DIR)
	$(RISCV_GCC) $(CFLAGS) -c -o $@ $<
$(BUILD_DIR)/rtos_portASM.o: $(PORT_DIR)/portASM.S | $(BUILD_DIR)
	$(RISCV_GCC) $(ASFLAGS) -c -o $@ $<

# Final link
$(APP_NAME): $(OBJS)
	$(RISCV_GCC) $(LDFLAGS) $(OBJS) $(LIBS) -o $@

$(APP_NAME).bin: $(APP_NAME)
	$(RISCV_OBJCOPY) -O binary $< $@
$(APP_NAME).hex: $(APP_NAME)
	$(RISCV_OBJCOPY) -O verilog $< $@
$(APP_NAME).dump: $(APP_NAME)
	$(RISCV_OBJDUMP) --disassemble-all -S $< > $@

clean:
	rm -rf $(BUILD_DIR)
	rm -f $(APP_NAME) $(APP_NAME).bin $(APP_NAME).hex $(APP_NAME).dump $(APP_NAME).map
