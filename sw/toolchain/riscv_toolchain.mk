# sw/toolchain/riscv_toolchain.mk
#
# Shared RISC-V bare-metal cross toolchain detection for project Makefiles.
#
# Prerequisites
# -------------
#   Include only after defining REPO_ROOT to the absolute repository root,
#   e.g. REPO_ROOT := $(abspath $(dir $(lastword $(MAKEFILE_LIST)))/../../..)
#
# Behaviour (same everywhere)
# ----------------------------
#   1. If RISCV_PATH is set in the environment / command line -> use as-is.
#   2. Else if $(RISCV_PREFIX)gcc exists on PATH -> RISCV_PATH := prefix of that gcc.
#   3. Else fall back to the vendored toolchain under
#        $(REPO_ROOT)/sw/tinyriscv/tests/toolchain/$(RISCV_VENDORED_GCC_RELEASE_DIR)
#
# Outputs
# -------
#   RISCV_PATH, RISCV_GCC, RISCV_AS, RISCV_OBJCOPY, RISCV_OBJDUMP,
#   RISCV_GXX, RISCV_GDB, RISCV_AR, RISCV_READELF
#
#   RISCV_GNU_TARGET_PREFIX -- absolute path prefix ending with riscv64-unknown-elf-
#       (matches legacy uses that expected .../bin/riscv64-unknown-elf- + gcc).
#
#   PICOLIBC_SPECS_DEFAULT -- path to apt picolibc specs (tinyriscv examples).
#
# Bump vendored fallback
# ----------------------
#   Change RISCV_VENDORED_GCC_RELEASE_DIR below (directory name under
#   sw/tinyriscv/tests/toolchain/).  sim/scripts/common.sh reads the same
#   variable from this file for offline resolution.

ifndef REPO_ROOT
$(error riscv_toolchain.mk: set REPO_ROOT to the repository root before including this file)
endif

RISCV_PREFIX ?= riscv64-unknown-elf-

# Offline bundle directory name (single knob).
RISCV_VENDORED_GCC_RELEASE_DIR ?= riscv64-unknown-elf-gcc-8.3.0-2020.04.0-x86_64-linux-ubuntu14

RISCV_VENDORED_PATH ?= $(REPO_ROOT)/sw/tinyriscv/tests/toolchain/$(RISCV_VENDORED_GCC_RELEASE_DIR)

ifeq ($(origin RISCV_PATH),undefined)
  _RISCV_SYS_GCC := $(shell command -v $(RISCV_PREFIX)gcc 2>/dev/null)
  ifneq ($(_RISCV_SYS_GCC),)
    RISCV_PATH := $(abspath $(dir $(_RISCV_SYS_GCC))/..)
  else
    RISCV_PATH := $(RISCV_VENDORED_PATH)
  endif
endif

_RISCV_BINDIR := $(abspath $(RISCV_PATH)/bin)

RISCV_GCC       := $(_RISCV_BINDIR)/$(RISCV_PREFIX)gcc
RISCV_AS        := $(_RISCV_BINDIR)/$(RISCV_PREFIX)as
RISCV_OBJCOPY   := $(_RISCV_BINDIR)/$(RISCV_PREFIX)objcopy
RISCV_OBJDUMP   := $(_RISCV_BINDIR)/$(RISCV_PREFIX)objdump
RISCV_GXX       := $(_RISCV_BINDIR)/$(RISCV_PREFIX)g++
RISCV_GDB       := $(_RISCV_BINDIR)/$(RISCV_PREFIX)gdb
RISCV_AR        := $(_RISCV_BINDIR)/$(RISCV_PREFIX)gcc-ar
RISCV_READELF   := $(_RISCV_BINDIR)/$(RISCV_PREFIX)readelf

# Legacy naming: full exec prefix (.../bin/riscv64-unknown-elf-)
RISCV_GNU_TARGET_PREFIX := $(_RISCV_BINDIR)/$(RISCV_PREFIX)

# Picolibc (apt: picolibc-riscv64-unknown-elf); used by tinyriscv/tests/example/common.mk
PICOLIBC_SPECS_DEFAULT ?= /usr/lib/picolibc/riscv64-unknown-elf/picolibc.specs
