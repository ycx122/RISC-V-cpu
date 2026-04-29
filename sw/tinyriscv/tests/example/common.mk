
# Toolchain: shared logic in sw/toolchain/riscv_toolchain.mk (PATH ->
# vendored).  REPO_ROOT is derived from this file's location
# (sw/tinyriscv/tests/example/common.mk -> four levels up to repo root).
COMMON_MK_DIR := $(dir $(lastword $(MAKEFILE_LIST)))
REPO_ROOT := $(abspath $(COMMON_MK_DIR)/../../../../)
include $(REPO_ROOT)/sw/toolchain/riscv_toolchain.mk

.PHONY: all
all: $(TARGET)

ASM_SRCS += $(COMMON_DIR)/start.S
ASM_SRCS += $(COMMON_DIR)/trap_entry.S

C_SRCS += $(COMMON_DIR)/init.c

C_SRCS += $(COMMON_DIR)/trap_handler.c
C_SRCS += $(COMMON_DIR)/lib/utils.c

C_SRCS += $(COMMON_DIR)/lib/xprintf.c
C_SRCS += $(COMMON_DIR)/lib/500a.c

C_SRCS += $(COMMON_DIR)/lib/my_string.c

ASM_SRCS += $(COMMON_DIR)/lib/arry.S

#C_SRCS += $(COMMON_DIR)/lib/uart.c
#C_SRCS += $(COMMON_DIR)/lib/flash_n25q.c
#C_SRCS += $(COMMON_DIR)/lib/spi.c

LINKER_SCRIPT := $(COMMON_DIR)/d.lds

INCLUDES += -I$(COMMON_DIR)

LDFLAGS += -T $(LINKER_SCRIPT) -nostartfiles -Wl,--gc-sections -Wl,--check-sections

ASM_OBJS := $(ASM_SRCS:.S=.o)
C_OBJS := $(C_SRCS:.c=.o)

LINK_OBJS += $(ASM_OBJS) $(C_OBJS)
LINK_DEPS += $(LINKER_SCRIPT)

CLEAN_OBJS += $(TARGET) $(LINK_OBJS) $(TARGET).dump $(TARGET).bin

# Some assembly files (start.S / trap_entry.S) use CSR / fence.i
# instructions. Binutils >= 2.38 (shipped with GCC >= 12) requires the
# `zicsr` / `zifencei` z-extensions to be listed explicitly in -march;
# the vendored 8.3.0 (binutils 2.32) rejects that spelling.  Probe the
# resolved toolchain once and silently append the extensions if they are
# accepted and not already present in $(RISCV_ARCH).
_RISCV_ZICSR_OK := $(shell $(RISCV_GCC) -march=rv32i_zicsr_zifencei -mabi=ilp32 -x c -c -o /dev/null - </dev/null 2>/dev/null && echo yes)
ifeq ($(_RISCV_ZICSR_OK),yes)
  ifeq ($(findstring _zicsr,$(RISCV_ARCH)),)
    RISCV_ARCH := $(RISCV_ARCH)_zicsr_zifencei
  endif
endif

# Hosted libc headers (apt GCC bare-metal): picolibc.specs compile hooks — sw/toolchain/riscv_picolib_cc.mk
include $(REPO_ROOT)/sw/toolchain/riscv_picolib_cc.mk

CFLAGS += -march=$(RISCV_ARCH)
CFLAGS += -mabi=$(RISCV_ABI)
CFLAGS += $(PICOLIBC_CC_CFLAGS)
#CFLAGS +=  -mcmodel=$(RISCV_MCMODEL) -ffunction-sections -fdata-sections -fno-builtin-printf -fno-builtin-malloc

$(TARGET): $(LINK_OBJS) $(LINK_DEPS) Makefile
	$(RISCV_GCC) $(CFLAGS) $(INCLUDES) $(LINK_OBJS) -o $@ $(LDFLAGS)
	$(RISCV_OBJCOPY) -O binary $@ $@.bin
	$(RISCV_OBJDUMP) --disassemble-all $@ > $@.dump

$(ASM_OBJS): %.o: %.S
	$(RISCV_GCC) $(CFLAGS) $(INCLUDES) -c -o $@ $<

$(C_OBJS): %.o: %.c
	$(RISCV_GCC) $(CFLAGS) $(INCLUDES) -c -o $@ $<

.PHONY: clean
clean:
	rm -f $(CLEAN_OBJS)
