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
#   MI_SMOKE_TIMEOUT  timeout passed to `timeout` (default: 30s).  The
#                    cached AXI ifetch path (I-Cache + 4-beat line fills +
#                    the testbench's #500 drain window after x26==1) can
#                    push the wall-clock runtime of a single mi_smoke run
#                    past 10s on Icarus, so the default is sized to
#                    absorb that without masking real hangs.

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
source "$repo_root/sim/scripts/common.sh"

linker_script="$repo_root/sw/tinyriscv/tests/example/d.lds"
src_file="$repo_root/sim/tests/mi_smoke.S"
timeout_val="${MI_SMOKE_TIMEOUT:-30s}"

if ! gcc_bin=$(find_riscv_tool gcc) \
   || ! objcopy_bin=$(find_riscv_tool objcopy) \
   || ! objdump_bin=$(find_riscv_tool objdump); then
    echo "Missing RISC-V toolchain (riscv64-unknown-elf-gcc et al.)" >&2
    echo "Install via: sudo apt install gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf" >&2
    exit 1
fi

for required in iverilog vvp timeout; do
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

march=$(find_riscv_march rv32im)

echo "[1/4] Building M-mode trap smoke program..."
"$gcc_bin" \
    -march="$march" -mabi=ilp32 \
    -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles \
    -T "$linker_script" \
    "$src_file" \
    -o "$build_dir/mi_smoke.elf"

echo "[2/4] Generating ROM image..."
"$objcopy_bin" -O verilog "$build_dir/mi_smoke.elf" "$build_dir/mi_smoke.verilog"
"$objdump_bin" --disassemble-all "$build_dir/mi_smoke.elf" >"$build_dir/mi_smoke.dump"

echo "[3/4] Compiling Icarus Verilog testbench..."
rtl_files=()
load_filelist "$repo_root/sim/filelist/tb_common.f"
load_filelist "$repo_root/sim/filelist/rtl_core.f"
load_filelist "$repo_root/sim/filelist/rtl_soc.f"
load_filelist "$repo_root/sim/filelist/sim_stubs.f"

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
