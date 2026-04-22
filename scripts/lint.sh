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

# Keep this list in sync with sim/smoke.sh so lint covers the same RTL
# set that is actually simulated. `sim/models/xilinx_compat.v` is added
# last so the Xilinx IP shims do not mask real issues in the core RTL.
rtl_files=(
    "$repo_root/rtl/soc/cpu_soc.v"
    "$repo_root/rtl/core/cpu_jh.v"
    "$repo_root/rtl/core/pipeline_regs.v"
    "$repo_root/rtl/core/hazard_ctrl.v"
    "$repo_root/rtl/core/flush_ctrl.v"
    "$repo_root/rtl/core/stop_cache.v"
    "$repo_root/rtl/core/branch_unit.v"
    "$repo_root/rtl/core/forward_mux.v"
    "$repo_root/rtl/core/mem_ctrl.v"
    "$repo_root/rtl/core/pc.v"
    "$repo_root/rtl/core/branch_pred.v"
    "$repo_root/rtl/core/id.v"
    "$repo_root/rtl/core/alu.v"
    "$repo_root/rtl/core/csr_reg.v"
    "$repo_root/rtl/core/regfile.v"
    "$repo_root/rtl/core/ju.v"
    "$repo_root/rtl/core/im2op.v"
    "$repo_root/rtl/core/otof1.v"
    "$repo_root/rtl/core/mul_div.v"
    "$repo_root/rtl/core/div_gen.v"
    "$repo_root/rtl/core/mul.v"
    "$repo_root/rtl/bus/axil_master_bridge.v"
    "$repo_root/rtl/bus/axil_slave_wrapper.v"
    "$repo_root/rtl/bus/axil_interconnect.v"
    "$repo_root/rtl/bus/axil_ifetch_bridge.v"
    "$repo_root/rtl/bus/icache.v"
    "$repo_root/rtl/memory/ram_c.v"
    "$repo_root/rtl/memory/rodata.v"
    "$repo_root/rtl/common/primitives/ram.v"
    "$repo_root/rtl/common/primitives/fifo.v"
    "$repo_root/rtl/peripherals/uart/rxtx.v"
    "$repo_root/rtl/peripherals/uart/cpu_uart.v"
    "$repo_root/rtl/peripherals/timer/clnt.v"
    "$repo_root/sim/models/xilinx_compat.v"
)

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
