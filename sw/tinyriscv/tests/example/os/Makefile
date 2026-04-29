RISCV_ARCH := rv32im
RISCV_ABI := ilp32
RISCV_MCMODEL := medlow


TARGET = os


#CFLAGS += -DSIMULATION
#CFLAGS += -O2
ASM_SRCS += arry.S
ASM_SRCS += os_entry.S
#LD
C_SFLAGS +=
INCLUDES += -I.
C_SRCS := \
	main.c \
	sched.c \



COMMON_DIR = ..
include ../common.mk
