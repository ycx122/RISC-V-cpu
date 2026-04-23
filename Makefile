# Top-level Makefile for the RISC-V CPU project.
#
# This is a thin wrapper around the existing sim/*.sh and scripts/lint.sh
# entry points.  The goal is to have a single discoverable command set
# ("make help") for the common developer flows, not to reimplement the
# build logic -- each target delegates to the corresponding shell script
# so the shell entry points remain usable on their own.
#
# Quickstart:
#   make lint          # static lint (Verilator preferred, iverilog fallback)
#   make isa           # run riscv-tests rv32ui + rv32um regression
#   make smoke         # minimal RV32IM smoke test
#   make smoke-mi      # M-mode trap / CLINT / PLIC smoke test
#   make bpu-bench     # branch predictor A/B benchmark (set BPU_COMPARE=1)
#   make bus-bench     # AXI bus latency microbenchmark
#   make dhrystone     # Dhrystone DMIPS/MHz
#   make os-demo       # cooperative-scheduler OS demo (sw/programs/os_demo)
#   make test          # lint + isa + smoke + smoke-mi   (no benches)
#   make bench         # bpu-bench + bus-bench           (no isa)
#   make all           # test + bench + dhrystone + os-demo
#
# Pass-through knobs:
#   MI_SMOKE_TIMEOUT=60s         -- override smoke-mi timeout
#   ISA_IVERILOG_DEFS="-DTCM_IFETCH"  -- pick a different fetch path
#   BPU_COMPARE=1                -- run bpu-bench with --compare (baseline vs BPU)
#
# The repository root is the only supported make invocation directory.

SHELL := /bin/bash

ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
SIM  := $(ROOT)/sim
SW   := $(ROOT)/sw
SCRIPTS := $(ROOT)/scripts

.DEFAULT_GOAL := help

# Helper: always run targets from the repo root.  Each recipe prefixes
# itself with `cd $(ROOT) &&` so that the shell scripts resolve their
# own $script_dir to this repository no matter where `make` was called.
RUN := cd "$(ROOT)" &&

# --------------------------------------------------------------------------
# Individual entry points
# --------------------------------------------------------------------------
.PHONY: lint
lint: ## Run static lint (Verilator if available, iverilog fallback)
	$(RUN) bash "$(SCRIPTS)/lint.sh"

.PHONY: isa
isa: ## Run sw/tinyriscv riscv-tests ISA regression (rv32ui + rv32um)
	$(RUN) bash "$(SIM)/run_isa.sh"

.PHONY: smoke
smoke: ## Build and run the minimal RV32IM smoke program
	$(RUN) bash "$(SIM)/smoke.sh"

.PHONY: smoke-mi
smoke-mi: ## Build and run the M-mode trap / CLINT / PLIC smoke program
	$(RUN) bash "$(SIM)/smoke_mi.sh"

.PHONY: bpu-bench
bpu-bench: ## Run the branch-predictor microbenchmark (BPU_COMPARE=1 for A/B)
ifeq ($(BPU_COMPARE),1)
	$(RUN) bash "$(SIM)/bpu_bench.sh" --compare
else
	$(RUN) bash "$(SIM)/bpu_bench.sh"
endif

.PHONY: bus-bench
bus-bench: ## Run the AXI bus latency microbenchmark
	$(RUN) bash "$(SIM)/bus_bench.sh"

.PHONY: dhrystone
dhrystone: ## Build and run Dhrystone from sw/tinyriscv/tests/example/dhyrstone
	$(RUN) bash "$(SIM)/run_dhrystone.sh"

.PHONY: os-demo
os-demo: ## Build sw/programs/os_demo and run it in simulation
	$(RUN) bash "$(SIM)/run_os_demo.sh"

# --------------------------------------------------------------------------
# Aggregate targets
# --------------------------------------------------------------------------
.PHONY: test
test: lint isa smoke smoke-mi ## Correctness regression (no perf microbenchmarks)

.PHONY: bench
bench: bpu-bench bus-bench ## Perf microbenchmarks only

.PHONY: all
all: test bench dhrystone os-demo ## Full regression + perf + end-to-end demo

# --------------------------------------------------------------------------
# Housekeeping
# --------------------------------------------------------------------------
.PHONY: clean
clean: ## Remove sim/output/ artifacts (logs, ROM images, waveforms)
	@rm -rf "$(SIM)/output/isa" "$(SIM)/output/cpu_test.out" \
	        "$(SIM)/output/dhrystone.log" "$(SIM)/waves/"*.vcd
	@echo "[clean] sim output removed"

.PHONY: distclean
distclean: clean ## clean + remove tinyriscv example object files
	@find "$(SW)/tinyriscv/tests/example" -maxdepth 4 \
	    \( -name '*.o' -o -name '*.bin' -o -name '*.dump' \) -delete 2>/dev/null || true
	@echo "[distclean] sw build artefacts removed"

# --------------------------------------------------------------------------
# Self-documenting help.  Any target with a `## ` trailing comment shows up.
# --------------------------------------------------------------------------
.PHONY: help
help:
	@echo "Available targets:"
	@awk 'BEGIN {FS = ":.*?## "} \
	      /^[a-zA-Z0-9_-]+:.*?## / {printf "  \033[36m%-14s\033[0m %s\n", $$1, $$2}' \
	      $(MAKEFILE_LIST)
	@echo ""
	@echo "Pass-through variables:"
	@echo "  BPU_COMPARE=1                   bpu-bench A/B vs disabled predictor"
	@echo "  MI_SMOKE_TIMEOUT=<s>            override smoke-mi vvp timeout"
	@echo "  ISA_IVERILOG_DEFS=-DTCM_IFETCH  switch fetch path for isa/smoke targets"
