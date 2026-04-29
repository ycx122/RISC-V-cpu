#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: sim/smoke.sh [--keep] [--help]

Builds a minimal RV32IM smoke-test program, compiles the Icarus Verilog
testbench, and runs the simulation until it reports TEST_PASS or fails.

Options:
  --keep    Keep the temporary build directory instead of deleting it
  --help    Show this help message

Environment:
  SMOKE_TIMEOUT   Simulation timeout passed to `timeout` (default: 10s)
EOF
}

keep_build_dir=0
while (($# > 0)); do
    case "$1" in
        --keep)
            keep_build_dir=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
source "$repo_root/sim/scripts/common.sh"

linker_script="$repo_root/sw/tinyriscv/tests/example/d.lds"
smoke_timeout="${SMOKE_TIMEOUT:-10s}"

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

build_dir=$(mktemp -d "${TMPDIR:-/tmp}/riscv-cpu-smoketest.XXXXXX")
cleanup() {
    if [[ "$keep_build_dir" -eq 0 ]]; then
        rm -rf "$build_dir"
    else
        echo "Kept build directory: $build_dir"
    fi
}
trap cleanup EXIT

cat >"$build_dir/minimal_div_pass.S" <<'EOF'
    .section .text
    .globl _start
_start:
    addi x1, x0, 121
    addi x2, x0, 11
    div  x3, x1, x2
    addi x4, x0, 11
    bne  x3, x4, fail
pass:
    addi x26, x0, 1
    addi x27, x0, 1
1:
    jal  x0, 1b
fail:
    addi x26, x0, 1
    addi x27, x0, 0
2:
    jal  x0, 2b
EOF

march=$(find_riscv_march rv32im)

echo "[1/4] Building minimal RV32IM smoke program..."
"$gcc_bin" \
    -march="$march" \
    -mabi=ilp32 \
    -T "$linker_script" \
    -nostdlib \
    -nostartfiles \
    "$build_dir/minimal_div_pass.S" \
    -o "$build_dir/minimal_div_pass.elf"

echo "[2/4] Generating ROM image..."
"$objcopy_bin" -O verilog \
    "$build_dir/minimal_div_pass.elf" \
    "$build_dir/minimal_div_pass.verilog"
"$objdump_bin" --disassemble-all \
    "$build_dir/minimal_div_pass.elf" \
    >"$build_dir/minimal_div_pass.dump"

echo "[3/4] Compiling Icarus Verilog testbench..."
rtl_files=()
load_filelist "$repo_root/sim/filelist/tb_common.f"
load_filelist "$repo_root/sim/filelist/rtl_core.f"
load_filelist "$repo_root/sim/filelist/rtl_soc.f"
load_filelist "$repo_root/sim/filelist/sim_stubs.f"

iverilog ${SMOKE_IVERILOG_DEFS:-} -o "$build_dir/cpu_test_smoke.out" -s cpu_test "${rtl_files[@]}"

echo "[4/4] Running simulation..."
if ! sim_output=$(timeout "$smoke_timeout" vvp -n "$build_dir/cpu_test_smoke.out" +IROM="$build_dir/minimal_div_pass.verilog" ${SMOKE_VVP_ARGS:-} 2>&1); then
    printf '%s\n' "$sim_output"
    echo "Smoke test failed or timed out after $smoke_timeout." >&2
    exit 1
fi

printf '%s\n' "$sim_output"

case "$sim_output" in
    *"TEST_PASS"*)
        echo "Smoke test passed."
        ;;
    *)
        echo "Simulation completed without TEST_PASS marker." >&2
        exit 1
        ;;
esac
