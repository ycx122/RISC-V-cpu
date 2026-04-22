RISCV_ARCH := rv32im
RISCV_ABI := ilp32
RISCV_MCMODEL := medlow


TARGET = dhry


CFLAGS += -DCFG_SIMULATION
CFLAGS += -DSIM_PASS_MARKER -DSIM_PANIC_ON_SYNC
CFLAGS += -O2
#ASM_SRCS +=
#LD
C_SFLAGS +=
#INCLUDES += -I.
C_SRCS := \
	dhry_1.c \
    dhry_2.c \
    dhry_stubs.c \

COMMON_DIR = ..
TOOLCHAIN_DIR = ../..
include ../common.mk