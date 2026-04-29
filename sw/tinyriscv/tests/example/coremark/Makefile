RISCV_ARCH := rv32i
RISCV_ABI := ilp32
RISCV_MCMODEL := medlow

TARGET := coremark

C_SRCS := \
	core_list_join.c \
	core_main.c \
	core_matrix.c \
	core_state.c \
	core_util.c \
	core_portme.c \

CFLAGS := 
CFLAGS += -DFLAGS_STR=\""$(CFLAGS)"\"
CFLAGS += -DITERATIONS=10000 -DPERFORMANCE_RUN=1

COMMON_DIR = ..
include ../common.mk
