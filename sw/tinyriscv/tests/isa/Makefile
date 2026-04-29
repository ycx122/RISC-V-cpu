#=======================================================================
# Makefile for riscv-tests/isa
#-----------------------------------------------------------------------

XLEN := 32

src_dir := .

REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../../..)
include $(REPO_ROOT)/sw/toolchain/riscv_toolchain.mk
export RISCV_PREFIX := $(RISCV_GNU_TARGET_PREFIX)

include $(src_dir)/rv32ui/Makefrag
include $(src_dir)/rv32um/Makefrag

default: all

#--------------------------------------------------------------------
# Toolchain (PATH -> vendored); RISCV_PREFIX exported for sub-makes
#--------------------------------------------------------------------

RISCV_GCC_OPTS ?= -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles

vpath %.S $(src_dir)

#------------------------------------------------------------
# Build assembly tests

%.dump: % 
	$(RISCV_OBJDUMP) --disassemble-all generated/$< > generated/$@
	$(RISCV_OBJCOPY) -O verilog generated/$<   generated/$<.verilog
	$(RISCV_OBJCOPY) -O binary generated/$<   generated/$<.bin


define compile_template

$$($(1)_p_tests): $(1)-p-%: $(1)/%.S
	$$(RISCV_GCC) $(2) $$(RISCV_GCC_OPTS) -I$(src_dir) -T$(src_dir)/link.ld $$< -o generated/$$@
$(1)_tests += $$($(1)_p_tests)

$(1)_tests_dump = $$(addsuffix .dump, $$($(1)_tests))

$(1): $$($(1)_tests_dump)

.PHONY: $(1)

tests += $$($(1)_tests)

endef

$(eval $(call compile_template,rv32ui,-march=rv32i -mabi=ilp32))
$(eval $(call compile_template,rv32um,-march=rv32im -mabi=ilp32))


tests_verilog = $(addsuffix .verilog, $(tests))
tests_dump = $(addsuffix .dump, $(tests))


#------------------------------------------------------------
# Default

all: $(tests_dump)

clean:
	rm -rf generated/*

