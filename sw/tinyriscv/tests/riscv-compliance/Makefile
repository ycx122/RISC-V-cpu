export RISCV_TARGET       ?= tinyriscv
TOOLCHAIN_ROOT ?= ../toolchain
export RISCV_PREFIX       ?= $(abspath $(TOOLCHAIN_ROOT)/riscv64-unknown-elf-gcc-8.3.0-2020.04.0-x86_64-linux-ubuntu14/bin/riscv64-unknown-elf-)

export ROOTDIR    := $(abspath .)
export TARGETDIR ?= $(ROOTDIR)/riscv-target


default: all


all:
	$(MAKE) RISCV_TARGET=$(RISCV_TARGET) RISCV_DEVICE=rv32i RISCV_PREFIX=$(RISCV_PREFIX) RISCV_ISA=rv32i run -C $(ROOTDIR)/riscv-test-suite/rv32i
	$(MAKE) RISCV_TARGET=$(RISCV_TARGET) RISCV_DEVICE=rv32im RISCV_PREFIX=$(RISCV_PREFIX) RISCV_ISA=rv32im run -C $(ROOTDIR)/riscv-test-suite/rv32im
	$(MAKE) RISCV_TARGET=$(RISCV_TARGET) RISCV_DEVICE=rv32Zicsr RISCV_PREFIX=$(RISCV_PREFIX) RISCV_ISA=rv32Zicsr run -C $(ROOTDIR)/riscv-test-suite/rv32Zicsr
	$(MAKE) RISCV_TARGET=$(RISCV_TARGET) RISCV_DEVICE=rv32Zifencei RISCV_PREFIX=$(RISCV_PREFIX) RISCV_ISA=rv32Zifencei run -C $(ROOTDIR)/riscv-test-suite/rv32Zifencei

clean:
	$(MAKE) clean -C $(ROOTDIR)/riscv-test-suite/rv32i
	$(MAKE) clean -C $(ROOTDIR)/riscv-test-suite/rv32im
	$(MAKE) clean -C $(ROOTDIR)/riscv-test-suite/rv32Zicsr
	$(MAKE) clean -C $(ROOTDIR)/riscv-test-suite/rv32Zifencei

