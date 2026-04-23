#!/usr/bin/env bash
# Static lint for the RISC-V CPU RTL.
#
# Prefers Verilator (fast, informative), falls back to Icarus Verilog's
# null target (syntax/elab check only). Never modifies any RTL.
#
# Usage:
#   bash scripts/lint.sh            # run with default warning set
#   LINT_STRICT=1 bash scripts/lint.sh  # also upgrade warnings to errors
set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)

# Shared RTL list + filelist loader.  Lint's top module is `cpu_soc`, so
# we explicitly skip tb_common.f (which carries sim/tb/cpu_test.v).  The
# Xilinx IP stubs come last so they don't mask real issues in core RTL.
source "$repo_root/sim/scripts/common.sh"
rtl_files=()
load_filelist "$repo_root/sim/filelist/rtl_core.f"
load_filelist "$repo_root/sim/filelist/rtl_soc.f"
load_filelist "$repo_root/sim/filelist/sim_stubs.f"

strict=${LINT_STRICT:-0}
exit_code=0

if command -v verilator >/dev/null 2>&1; then
    echo "[lint] Using Verilator $(verilator --version | head -1)"

    # -Wall turns on the common warning set; we explicitly suppress
    # a handful of warnings that are pervasive in this (legacy) design
    # and would swamp the real signal. Remove a `-Wno-*` line here when
    # you start cleaning up that class of issue.
    args=(
        --lint-only
        -Wall
        -Wno-UNUSED
        -Wno-UNDRIVEN
        -Wno-DECLFILENAME
        -Wno-WIDTH
        -Wno-CASEINCOMPLETE
        -Wno-COMBDLY
        -Wno-INITIALDLY
        -Wno-MULTIDRIVEN
        -Wno-BLKSEQ
        --top-module cpu_soc
    )

    if [[ "$strict" != "0" ]]; then
        args+=(-Wpedantic -Werror-IMPLICIT -Werror-PINMISSING)
    fi

    if ! verilator "${args[@]}" "${rtl_files[@]}"; then
        exit_code=1
    fi
elif command -v iverilog >/dev/null 2>&1; then
    echo "[lint] Verilator not found; falling back to Icarus Verilog elaboration check."
    echo "[lint] Install Verilator for a much stronger lint: sudo apt install verilator"

    # `-t null` tells iverilog to parse and elaborate but emit nothing.
    # It catches syntax errors, undeclared nets and port-width mismatches
    # but is much weaker than Verilator.
    if ! iverilog -t null -Wall -s cpu_soc "${rtl_files[@]}"; then
        exit_code=1
    fi
else
    echo "[lint] Neither verilator nor iverilog is installed." >&2
    echo "[lint] Install one of:" >&2
    echo "[lint]   sudo apt install verilator   # preferred" >&2
    echo "[lint]   sudo apt install iverilog    # fallback" >&2
    exit 2
fi

if [[ "$exit_code" -eq 0 ]]; then
    echo "[lint] OK"
else
    echo "[lint] Issues found (exit $exit_code)" >&2
fi

exit "$exit_code"
