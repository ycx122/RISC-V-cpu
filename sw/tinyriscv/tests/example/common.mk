
TOOLCHAIN_ROOT ?= $(TOOLCHAIN_DIR)/toolchain
RISCV_PATH ?= $(TOOLCHAIN_ROOT)/riscv64-unknown-elf-gcc-8.3.0-2020.04.0-x86_64-linux-ubuntu14

RISCV_GCC     := $(abspath $(RISCV_PATH)/bin/riscv64-unknown-elf-gcc)
RISCV_AS      := $(abspath $(RISCV_PATH)/bin/riscv64-unknown-elf-as)
RISCV_GXX     := $(abspath $(RISCV_PATH)/bin/riscv64-unknown-elf-g++)
RISCV_OBJDUMP := $(abspath $(RISCV_PATH)/bin/riscv64-unknown-elf-objdump)
RISCV_GDB     := $(abspath $(RISCV_PATH)/bin/riscv64-unknown-elf-gdb)
RISCV_AR      := $(abspath $(RISCV_PATH)/bin/riscv64-unknown-elf-gcc-ar)
RISCV_OBJCOPY := $(abspath $(RISCV_PATH)/bin/riscv64-unknown-elf-objcopy)
RISCV_READELF := $(abspath $(RISCV_PATH)/bin/riscv64-unknown-elf-readelf)

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

CFLAGS += -march=$(RISCV_ARCH)
CFLAGS += -mabi=$(RISCV_ABI)
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
