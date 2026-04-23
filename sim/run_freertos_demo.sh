#!/usr/bin/env bash
#
# sim/run_freertos_demo.sh
#
# End-to-end test for the FreeRTOS V11.1.0 port at
# sw/programs/freertos_demo/.  Builds the ROM image, compiles the same
# RTL filelist used by sim/run_os_demo.sh, and runs the testbench until
# OS_DEMO_PASS appears on the UART or we hit the cycle cap.
#
# Exit code 0 on pass, non-zero otherwise.
#
# Flags:
#   --keep   keep the temporary vvp build dir
#   --help   show this help
#
# Environment overrides:
#   FREERTOS_DEMO_TIMEOUT     shell-level timeout for vvp (default 60s)
#   FREERTOS_DEMO_MAX_CYCLES  testbench cycle cap  (default 6000000)
#   FREERTOS_IVERILOG_DEFS    extra -D flags for iverilog (e.g. -DTCM_IFETCH)
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: sim/run_freertos_demo.sh [--keep] [--help]
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

app_dir="$repo_root/sw/programs/freertos_demo"

demo_timeout="${FREERTOS_DEMO_TIMEOUT:-600s}"
demo_max_cycles="${FREERTOS_DEMO_MAX_CYCLES:-6000000}"

for required in iverilog vvp timeout make; do
    if ! command -v "$required" >/dev/null 2>&1; then
        echo "Missing required tool: $required" >&2
        exit 1
    fi
done

build_dir=$(mktemp -d "${TMPDIR:-/tmp}/riscv-cpu-freertos.XXXXXX")
cleanup() {
    if [[ "$keep_build_dir" -eq 0 ]]; then
        rm -rf "$build_dir"
    else
        echo "Kept build directory: $build_dir"
    fi
}
trap cleanup EXIT

echo "[1/3] Building sw/programs/freertos_demo..."
make -C "$app_dir" >/dev/null
cp "$app_dir/freertos_demo.hex" "$build_dir/freertos_demo.hex"

echo "[2/3] Compiling testbench..."
source "$repo_root/sim/scripts/common.sh"
rtl_files=()
load_filelist "$repo_root/sim/filelist/tb_common.f"
load_filelist "$repo_root/sim/filelist/rtl_core.f"
load_filelist "$repo_root/sim/filelist/rtl_soc.f"
load_filelist "$repo_root/sim/filelist/sim_stubs.f"

iverilog ${FREERTOS_IVERILOG_DEFS:-} \
    -o "$build_dir/cpu_test_freertos.out" \
    -s cpu_test "${rtl_files[@]}"

echo "[3/3] Running simulation (+MAX_CYCLES=$demo_max_cycles, timeout=$demo_timeout)..."
set +e
sim_output=$(timeout "$demo_timeout" vvp -n "$build_dir/cpu_test_freertos.out" \
    +IROM="$build_dir/freertos_demo.hex" \
    +MAX_CYCLES="$demo_max_cycles" \
    +UART_PASS_PATTERN=OS_DEMO_PASS \
    "+UART_FAIL_PATTERN=${FREERTOS_DEMO_FAIL_PATTERN:-UNHANDLED}" \
    2>&1)
rc=$?
set -e

printf '%s\n' "$sim_output"

if [[ $rc -ne 0 ]]; then
    echo "[freertos_demo] vvp exited with status $rc (timeout=$demo_timeout)." >&2
    exit $rc
fi

case "$sim_output" in
    *"TEST_FAIL"*)
        echo "[freertos_demo] FAIL" >&2
        exit 1
        ;;
    *"UART_PASS_PATTERN matched"*"TEST_PASS"*|*"TEST_PASS"*"UART_PASS_PATTERN"*)
        echo "[freertos_demo] PASS"
        ;;
    *"OS_DEMO_PASS"*)
        echo "[freertos_demo] PASS (banner printed but testbench glue unrecognised)"
        ;;
    *)
        echo "[freertos_demo] No pass marker found in simulation output." >&2
        exit 1
        ;;
esac
