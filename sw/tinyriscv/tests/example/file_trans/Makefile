RISCV_ARCH := rv32im
RISCV_ABI := ilp32
RISCV_MCMODEL := medlow


TARGET = file_trans


#CFLAGS += -DSIMULATION
#CFLAGS += -O2
ASM_SRCS += arry.S
#ASM_SRCS += os_entry.S
#LD
C_SFLAGS +=
INCLUDES += -I.
C_SRCS := \
	main.c \



COMMON_DIR = ..
TOOLCHAIN_DIR = ../..
include ../common.mk
