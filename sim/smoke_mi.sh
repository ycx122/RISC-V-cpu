#!/usr/bin/env bash
# Machine-mode trap smoke test.
#
# Builds sim/tests/mi_smoke.S, feeds it to the same cpu_test testbench, and
# waits for the standard x26/x27 PASS protocol. This is our equivalent of
# the upstream rv32mi-p-* regression: the repo ships only rv32ui / rv32um
# source, so we hand-write a small M-mode exception round-trip instead.
#
# Usage:
#   bash sim/smoke_mi.sh [--keep]
#
# Environment:
#   MI_SMOKE_TIMEOUT  timeout passed to `timeout` (default: 10s)

set -euo pipefail

keep_build_dir=0
while (($# > 0)); do
    case "$1" in
        --keep)  keep_build_dir=1; shift ;;
        --help|-h)
            sed -n '2,14p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)

toolbin="$repo_root/sw/tinyriscv/tests/toolchain/riscv64-unknown-elf-gcc-8.3.0-2020.04.0-x86_64-linux-ubuntu14/bin"
linker_script="$repo_root/sw/tinyriscv/tests/example/d.lds"
src_file="$repo_root/sim/tests/mi_smoke.S"
timeout_val="${MI_SMOKE_TIMEOUT:-10s}"

gcc_bin="$toolbin/riscv64-unknown-elf-gcc"
objcopy_bin="$toolbin/riscv64-unknown-elf-objcopy"
objdump_bin="$toolbin/riscv64-unknown-elf-objdump"

for required in "$gcc_bin" "$objcopy_bin" "$objdump_bin" iverilog vvp timeout; do
    if ! command -v "$required" >/dev/null 2>&1; then
        echo "Missing required tool: $required" >&2
        exit 1
    fi
done

build_dir=$(mktemp -d "${TMPDIR:-/tmp}/riscv-cpu-mi-smoke.XXXXXX")
cleanup() {
    if [[ "$keep_build_dir" -eq 0 ]]; then rm -rf "$build_dir"
    else echo "Kept build directory: $build_dir"; fi
}
trap cleanup EXIT

echo "[1/4] Building M-mode trap smoke program..."
"$gcc_bin" \
    -march=rv32im -mabi=ilp32 \
    -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles \
    -T "$linker_script" \
    "$src_file" \
    -o "$build_dir/mi_smoke.elf"

echo "[2/4] Generating ROM image..."
"$objcopy_bin" -O verilog "$build_dir/mi_smoke.elf" "$build_dir/mi_smoke.verilog"
"$objdump_bin" --disassemble-all "$build_dir/mi_smoke.elf" >"$build_dir/mi_smoke.dump"

echo "[3/4] Compiling Icarus Verilog testbench..."
rtl_files=(
    "$repo_root/sim/tb/cpu_test.v"
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
    "$repo_root/sim/models/xilinx_compat.v"
    "$repo_root/rtl/core/mul.v"
    "$repo_root/rtl/interconnect/addr2c.v"
    "$repo_root/rtl/memory/ram_c.v"
    "$repo_root/rtl/common/primitives/ram.v"
    "$repo_root/rtl/peripherals/uart/rxtx.v"
    "$repo_root/rtl/peripherals/timer/clnt.v"
    "$repo_root/rtl/memory/rodata.v"
    "$repo_root/rtl/peripherals/uart/cpu_uart.v"
    "$repo_root/rtl/common/primitives/fifo.v"
)

iverilog -o "$build_dir/cpu_test_mi.out" -s cpu_test ${MI_IVERILOG_DEFS:-} "${rtl_files[@]}"

echo "[4/4] Running simulation..."
if ! sim_output=$(timeout "$timeout_val" vvp -n "$build_dir/cpu_test_mi.out" +IROM="$build_dir/mi_smoke.verilog" +EINT_AT=3000000 ${MI_VVP_ARGS:-} 2>&1); then
    rc=$?
    printf '%s\n' "$sim_output"
    if [[ "$rc" -eq 124 ]]; then
        echo "M-mode smoke TIMED OUT after $timeout_val." >&2
    else
        echo "M-mode smoke failed (rc=$rc)." >&2
    fi
    exit 1
fi

printf '%s\n' "$sim_output"

case "$sim_output" in
    *"TEST_PASS"*)
        echo "M-mode trap smoke passed."
        ;;
    *)
        echo "Simulation completed without TEST_PASS marker." >&2
        exit 1
        ;;
esac
