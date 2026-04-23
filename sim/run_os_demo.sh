#!/usr/bin/env bash
#
# sim/run_os_demo.sh
#
# End-to-end test for the sw/bsp/ BSP.  Builds sw/programs/os_demo/,
# drops the ROM image into the testbench, and runs it under vvp until
# the program prints its OS_DEMO_PASS banner (matched by the testbench
# via +UART_PASS_PATTERN) or we hit the cycle cap (+MAX_CYCLES).
#
# Exit code 0 on pass, non-zero on anything else.
#
# Flags:
#   --keep   keep the temporary vvp build dir
#   --help   show this help
#
# Environment overrides:
#   OS_DEMO_TIMEOUT     shell-level timeout for vvp (default 30s)
#   OS_DEMO_MAX_CYCLES  testbench cycle cap  (default 500000)
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: sim/run_os_demo.sh [--keep] [--help]
EOF
}

keep_build_dir=0
while (($# > 0)); do
    case "$1" in
        --keep) keep_build_dir=1; shift ;;
        --help|-h) usage; exit 0 ;;
        *) echo "Unknown option: $1" >&2; usage >&2; exit 1 ;;
    esac
done

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)

app_dir="$repo_root/sw/programs/os_demo"

os_demo_timeout="${OS_DEMO_TIMEOUT:-30s}"
os_demo_max_cycles="${OS_DEMO_MAX_CYCLES:-500000}"

for required in iverilog vvp timeout make; do
    if ! command -v "$required" >/dev/null 2>&1; then
        echo "Missing required tool: $required" >&2
        exit 1
    fi
done

build_dir=$(mktemp -d "${TMPDIR:-/tmp}/riscv-cpu-os-demo.XXXXXX")
cleanup() {
    if [[ "$keep_build_dir" -eq 0 ]]; then
        rm -rf "$build_dir"
    else
        echo "Kept build directory: $build_dir"
    fi
}
trap cleanup EXIT

echo "[1/3] Building sw/programs/os_demo..."
make -C "$app_dir" >/dev/null
cp "$app_dir/os_demo.hex" "$build_dir/os_demo.hex"

echo "[2/3] Compiling testbench..."
source "$repo_root/sim/scripts/common.sh"
rtl_files=()
load_filelist "$repo_root/sim/filelist/tb_common.f"
load_filelist "$repo_root/sim/filelist/rtl_core.f"
load_filelist "$repo_root/sim/filelist/rtl_soc.f"
load_filelist "$repo_root/sim/filelist/sim_stubs.f"

iverilog ${OS_DEMO_IVERILOG_DEFS:-} \
    -o "$build_dir/cpu_test_os_demo.out" \
    -s cpu_test "${rtl_files[@]}"

echo "[3/3] Running simulation (+MAX_CYCLES=$os_demo_max_cycles)..."
set +e
sim_output=$(timeout "$os_demo_timeout" vvp -n "$build_dir/cpu_test_os_demo.out" \
    +IROM="$build_dir/os_demo.hex" \
    +MAX_CYCLES="$os_demo_max_cycles" \
    +UART_PASS_PATTERN=OS_DEMO_PASS \
    +UART_FAIL_PATTERN=UNHANDLED \
    2>&1)
rc=$?
set -e

printf '%s\n' "$sim_output"

if [[ $rc -ne 0 ]]; then
    echo "[os_demo] vvp exited with status $rc (timeout=$os_demo_timeout)." >&2
    exit $rc
fi

# `UART_PASS_PATTERN matched` comes first (tb prints that line on the
# UART, *then* prints the TEST_PASS ASCII banner).  Matching on either
# tag is enough; the shell-side bash glob just needs both to be present
# in some order.
case "$sim_output" in
    *"TEST_FAIL"*)
        echo "[os_demo] FAIL" >&2
        exit 1
        ;;
    *"UART_PASS_PATTERN matched"*"TEST_PASS"*|*"TEST_PASS"*"UART_PASS_PATTERN"*)
        echo "[os_demo] PASS"
        ;;
    *"OS_DEMO_PASS"*)
        echo "[os_demo] PASS (banner printed but testbench glue unrecognised)"
        ;;
    *)
        echo "[os_demo] No pass marker found in simulation output." >&2
        exit 1
        ;;
esac
