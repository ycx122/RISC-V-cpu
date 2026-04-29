#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: sim/run_dhrystone.sh [--keep] [--help]

Build the Dhrystone example, compile the Icarus Verilog testbench, run the
simulation, and mirror the UART console into both stdout and
`sim/output/dhrystone.log`.

Options:
  --keep    Keep the temporary build directory instead of deleting it
  --help    Show this help message

Environment:
  DHRYSTONE_TIMEOUT        Simulation timeout passed to `timeout` (default: 45s)
  DHRYSTONE_IVERILOG_DEFS  Extra defines/options passed to `iverilog`
  DHRYSTONE_VVP_ARGS       Extra plusargs/options passed to `vvp`
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

example_dir="$repo_root/sw/tinyriscv/tests/example/dhyrstone"
log_dir="$repo_root/sim/output"
log_file="$log_dir/dhrystone.log"
dhrystone_timeout="${DHRYSTONE_TIMEOUT:-45s}"

if ! objcopy_bin=$(find_riscv_tool objcopy); then
    echo "Missing riscv64-unknown-elf-objcopy" >&2
    echo "Install via: sudo apt install gcc-riscv64-unknown-elf binutils-riscv64-unknown-elf" >&2
    exit 1
fi

for required in make iverilog vvp timeout; do
    if ! command -v "$required" >/dev/null 2>&1; then
        echo "Missing required tool: $required" >&2
        exit 1
    fi
done

build_dir=$(mktemp -d "${TMPDIR:-/tmp}/riscv-cpu-dhrystone.XXXXXX")
cleanup() {
    if [[ "$keep_build_dir" -eq 0 ]]; then
        rm -rf "$build_dir"
    else
        echo "Kept build directory: $build_dir"
    fi
}
trap cleanup EXIT

mkdir -p "$log_dir"

read -r -a extra_iverilog_defs <<< "${DHRYSTONE_IVERILOG_DEFS:-}"
read -r -a extra_vvp_args <<< "${DHRYSTONE_VVP_ARGS:-}"

echo "[1/4] Building Dhrystone software image..."
(
    cd "$example_dir"
    make clean
    make
)

echo "[2/4] Generating ROM image..."
"$objcopy_bin" -O verilog \
    "$example_dir/dhry" \
    "$build_dir/dhry.verilog"

echo "[3/4] Compiling Icarus Verilog testbench..."
rtl_files=()
load_filelist "$repo_root/sim/filelist/tb_common.f"
load_filelist "$repo_root/sim/filelist/rtl_core.f"
load_filelist "$repo_root/sim/filelist/rtl_soc.f"
load_filelist "$repo_root/sim/filelist/sim_stubs.f"

iverilog "${extra_iverilog_defs[@]}" \
    -o "$build_dir/cpu_test_dhrystone.out" \
    -s cpu_test \
    "${rtl_files[@]}"

echo "[4/4] Running simulation..."
if ! sim_output=$(timeout "$dhrystone_timeout" \
        vvp -n "$build_dir/cpu_test_dhrystone.out" \
        +IROM="$build_dir/dhry.verilog" \
        "${extra_vvp_args[@]}" 2>&1); then
    printf '%s\n' "$sim_output" | tee "$log_file"
    echo "Dhrystone simulation failed or timed out after $dhrystone_timeout." >&2
    echo "Log written to: $log_file" >&2
    exit 1
fi

printf '%s\n' "$sim_output" | tee "$log_file"

case "$sim_output" in
    *"TEST_PASS"*)
        echo "[dhrystone] PASS"
        echo "Log written to: $log_file"
        ;;
    *)
        echo "Simulation completed without TEST_PASS marker." >&2
        echo "Log written to: $log_file" >&2
        exit 1
        ;;
esac
