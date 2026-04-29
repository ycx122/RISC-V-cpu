#!/usr/bin/env bash
# Run the upstream riscv-tests ISA regression suite against this CPU.
#
# The testbench in sim/tb/cpu_test.v already follows the standard
# "x26==1 => finished, x27==1 => pass" protocol, so each test image
# can be fed to the same compiled simulation via +IROM=<hex>.
#
# The pre-generated Verilog-hex images live under
# sw/tinyriscv/tests/isa/generated/ and cover rv32ui + rv32um.
#
# Usage:
#   bash sim/run_isa.sh                    # run every supported test
#   bash sim/run_isa.sh --only 'rv32um-*'  # filter by shell glob on test name
#   bash sim/run_isa.sh --skip 'rv32ui-p-l*' --skip 'rv32ui-p-s[bh]'
#   bash sim/run_isa.sh add sub mul        # positional args are additive filters
#
# Environment:
#   ISA_TIMEOUT       Per-test timeout passed to `timeout` (default: 20s)
#   ISA_KEEP_BUILD=1  Keep the compiled simulation binary on exit
#
# Exit code:
#   0  iff every test that is not explicitly in the SKIP_LIST below reported
#      TEST_PASS within the timeout. Otherwise non-zero.

set -uo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)

tb_file="$repo_root/sim/tb/cpu_test.v"
images_dir="$repo_root/sw/tinyriscv/tests/isa/generated"
log_dir="$repo_root/sim/output/isa"

# Keep the RTL list in sync with sim/smoke.sh. If you add a file to smoke.sh,
# add it here too.
source "$repo_root/sim/scripts/common.sh"
rtl_files=()
load_filelist "$repo_root/sim/filelist/tb_common.f"
load_filelist "$repo_root/sim/filelist/rtl_core.f"
load_filelist "$repo_root/sim/filelist/rtl_soc.f"
load_filelist "$repo_root/sim/filelist/sim_stubs.f"

# Tests we deliberately skip because the processor does not implement
# the required extension / feature. See README "ISA 测试限制与架构边界".
# Update this list as features are added.
declare -a SKIP_LIST=(
    # fence.i itself is now decoded (see id.v opcode 0001111) and drains
    # pending stores in cpu_jh.v (fence_stall gates stop_control).
    # rv32ui-p-fence_i is still skipped because it exercises self-modifying
    # code: it stores into the .text region in the 0x00000000 window, which
    # on this SoC is fronted by rodata.v (a read-only ROM controller).
    # Enabling this test would require giving rodata.v a store path into
    # i_rom port A, which is an SoC/memory-subsystem change rather than
    # a CPU-core one.
    "rv32ui-p-fence_i"   # SoC ROM controller is read-only (no self-modifying code)
)

# Tests that are currently expected to FAIL because of known architectural
# gaps rather than recent regressions. The run is still green when these
# fail; only tracking drift (a new failure outside this list, or an
# unexpected pass) counts as a real change.
#
# The sb/sh/sw store tests used to require the `.data` initializer pattern
# (e.g. 0xef / 0xbeef bytes in `tdat`) to be present in RAM at reset time.
# Simulation now pre-loads that pattern through the `+DRAM=<file>` channel
# in sim/tb/cpu_test.v (see the `dram_init_bytes` block), so all three are
# expected to PASS and this list is empty.  Keep it as an empty array so
# the XPASS/xfail accounting logic still works if we add entries later.
declare -a EXPECTED_FAIL_LIST=()

# -------- argument parsing --------------------------------------------------

include_patterns=()
skip_patterns=()

usage() {
    sed -n '2,25p' "$0"
}

while (($# > 0)); do
    case "$1" in
        --only)
            [[ $# -ge 2 ]] || { echo "--only needs a pattern" >&2; exit 1; }
            include_patterns+=("$2")
            shift 2
            ;;
        --skip)
            [[ $# -ge 2 ]] || { echo "--skip needs a pattern" >&2; exit 1; }
            skip_patterns+=("$2")
            shift 2
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        --)
            shift
            break
            ;;
        -*)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
        *)
            include_patterns+=("$1")
            shift
            ;;
    esac
done

# -------- tool checks -------------------------------------------------------

for required in iverilog vvp timeout; do
    if ! command -v "$required" >/dev/null 2>&1; then
        echo "Missing required tool: $required" >&2
        exit 1
    fi
done

if [[ ! -d "$images_dir" ]]; then
    echo "ISA image directory not found: $images_dir" >&2
    exit 1
fi

isa_timeout="${ISA_TIMEOUT:-20s}"

mkdir -p "$log_dir"

# -------- locate riscv objcopy (for +DRAM preload) -------------------------
#
# The testbench supports a `+DRAM=<byte-hex-file>` plusarg that pre-loads
# the `.data` segment into simulated RAM (see sim/tb/cpu_test.v).  Extract
# each test's `.data` bytes from its ELF using whichever RISC-V objcopy the
# `find_riscv_tool` helper resolves (PATH > $RISCV_PATH > vendored 8.3.0).
# If none is available, skip the preload (tests that depend on initialized
# `.data`, currently rv32ui-p-s{b,h}, will fail but the rest still run).
if ! riscv_objcopy=$(find_riscv_tool objcopy); then
    echo "[isa] WARN: riscv64-unknown-elf-objcopy not found; skipping +DRAM preload"
    riscv_objcopy=""
fi

# -------- build simulation once --------------------------------------------

build_dir=$(mktemp -d "${TMPDIR:-/tmp}/riscv-cpu-isa.XXXXXX")
cleanup() {
    if [[ "${ISA_KEEP_BUILD:-0}" == "0" ]]; then
        rm -rf "$build_dir"
    else
        echo "[isa] Kept build dir: $build_dir"
    fi
}
trap cleanup EXIT

sim_bin="$build_dir/cpu_test_isa.out"

# Extra iverilog defines can be passed through ISA_IVERILOG_DEFS, e.g.
# ISA_IVERILOG_DEFS='-DTCM_IFETCH' bash sim/run_isa.sh to regress the
# legacy direct-BRAM ifetch fallback instead of the AXI path.
read -r -a _isa_extra_defs <<< "${ISA_IVERILOG_DEFS:-}"

echo "[isa] Compiling testbench (iverilog)..."
if ! iverilog -o "$sim_bin" -s cpu_test "${_isa_extra_defs[@]}" "${rtl_files[@]}" 2>"$build_dir/compile.log"; then
    cat "$build_dir/compile.log" >&2
    echo "[isa] Compilation failed." >&2
    exit 1
fi

# -------- collect test list -------------------------------------------------

mapfile -t all_images < <(cd "$images_dir" && ls *.verilog 2>/dev/null | LC_ALL=C sort)
if [[ ${#all_images[@]} -eq 0 ]]; then
    echo "[isa] No *.verilog images found under $images_dir" >&2
    exit 1
fi

# Returns 0 if the test name matches any of the given shell patterns.
name_matches() {
    local name="$1"
    shift
    local pat
    for pat in "$@"; do
        # Accept either the bare test name (e.g. 'add') or the full id
        # (e.g. 'rv32ui-p-add'). Both are matched as shell globs.
        # shellcheck disable=SC2053
        if [[ "$name" == $pat ]] || [[ "$name" == *"-$pat" ]]; then
            return 0
        fi
    done
    return 1
}

# Returns 0 if name is in the static SKIP_LIST.
is_skipped() {
    local name="$1"
    local skip
    for skip in "${SKIP_LIST[@]}"; do
        if [[ "$name" == "$skip" ]]; then
            return 0
        fi
    done
    return 1
}

# Returns 0 if name is listed as an expected failure.
is_expected_fail() {
    local name="$1"
    local xf
    for xf in "${EXPECTED_FAIL_LIST[@]}"; do
        if [[ "$name" == "$xf" ]]; then
            return 0
        fi
    done
    return 1
}

selected=()
for image in "${all_images[@]}"; do
    name="${image%.verilog}"
    if ((${#include_patterns[@]} > 0)); then
        if ! name_matches "$name" "${include_patterns[@]}"; then
            continue
        fi
    fi
    if ((${#skip_patterns[@]} > 0)); then
        if name_matches "$name" "${skip_patterns[@]}"; then
            continue
        fi
    fi
    selected+=("$name")
done

if [[ ${#selected[@]} -eq 0 ]]; then
    echo "[isa] No tests matched the given filters." >&2
    exit 1
fi

# -------- run ---------------------------------------------------------------

pass_list=()
fail_list=()        # unexpected failures (regressions)
timeout_list=()     # unexpected timeouts (regressions)
skip_list=()
xfail_list=()       # expected failures that did fail (OK, known gap)
xpass_list=()       # expected-to-fail tests that surprisingly passed

start_ts=$(date +%s)

for name in "${selected[@]}"; do
    if is_skipped "$name"; then
        printf '[isa] %-22s SKIP (known-unsupported)\n' "$name"
        skip_list+=("$name")
        continue
    fi

    image="$images_dir/$name.verilog"
    elf="$images_dir/$name"
    log="$log_dir/$name.log"

    # Build the `.data` preload hex (empty file is fine when the section
    # doesn't exist) so the sim can `$readmemh` it via +DRAM.
    dram_args=()
    if [[ -n "$riscv_objcopy" && -f "$elf" ]]; then
        data_bin="$build_dir/$name.data.bin"
        data_hex="$build_dir/$name.data.hex"
        if "$riscv_objcopy" -O binary -j .data "$elf" "$data_bin" 2>/dev/null; then
            if [[ -s "$data_bin" ]]; then
                xxd -c 1 -p "$data_bin" > "$data_hex"
                dram_args=(+DRAM="$data_hex")
            fi
        fi
    fi

    t0=$(date +%s)
    if timeout "$isa_timeout" vvp -n "$sim_bin" +IROM="$image" "${dram_args[@]}" >"$log" 2>&1; then
        rc=0
    else
        rc=$?
    fi
    t1=$(date +%s)
    dt=$((t1 - t0))

    expected_fail=0
    if is_expected_fail "$name"; then
        expected_fail=1
    fi

    if grep -q 'TEST_PASS' "$log"; then
        if [[ "$expected_fail" -eq 1 ]]; then
            printf '[isa] %-22s XPASS (%ds)  !! expected-fail list is stale\n' \
                "$name" "$dt"
            xpass_list+=("$name")
        else
            printf '[isa] %-22s PASS (%ds)\n' "$name" "$dt"
            pass_list+=("$name")
        fi
    elif grep -q 'TEST_FAIL' "$log"; then
        fail_num=$(grep -E 'fail testnum' "$log" | head -1 | sed -E 's/.*= *//')
        if [[ "$expected_fail" -eq 1 ]]; then
            printf '[isa] %-22s xfail (testnum=%s, %ds)\n' \
                "$name" "${fail_num:-?}" "$dt"
            xfail_list+=("$name")
        else
            printf '[isa] %-22s FAIL (testnum=%s, %ds)  log: %s\n' \
                "$name" "${fail_num:-?}" "$dt" "$log"
            fail_list+=("$name")
        fi
    elif [[ "$rc" -eq 124 ]]; then
        if [[ "$expected_fail" -eq 1 ]]; then
            printf '[isa] %-22s xfail (timeout, %ss)\n' "$name" "$isa_timeout"
            xfail_list+=("$name")
        else
            printf '[isa] %-22s TIMEOUT (%ss)  log: %s\n' \
                "$name" "$isa_timeout" "$log"
            timeout_list+=("$name")
        fi
    else
        printf '[isa] %-22s UNKNOWN (rc=%d, %ds)  log: %s\n' \
            "$name" "$rc" "$dt" "$log"
        fail_list+=("$name")
    fi
done

end_ts=$(date +%s)
elapsed=$((end_ts - start_ts))

# -------- summary -----------------------------------------------------------

echo
echo "===================== ISA regression summary ====================="
printf 'Total selected : %d  (of %d images)\n' "${#selected[@]}" "${#all_images[@]}"
printf 'Passed         : %d\n' "${#pass_list[@]}"
printf 'Failed (new)   : %d\n' "${#fail_list[@]}"
printf 'Timed out (new): %d\n' "${#timeout_list[@]}"
printf 'xfail (known)  : %d\n' "${#xfail_list[@]}"
printf 'xpass (!!)     : %d\n' "${#xpass_list[@]}"
printf 'Skipped        : %d\n' "${#skip_list[@]}"
printf 'Wall time      : %ds  (per-test timeout %s)\n' "$elapsed" "$isa_timeout"

if ((${#fail_list[@]} > 0)); then
    echo
    echo "NEW failures (regressions):"
    printf '  - %s\n' "${fail_list[@]}"
fi
if ((${#timeout_list[@]} > 0)); then
    echo
    echo "NEW timeouts (regressions):"
    printf '  - %s\n' "${timeout_list[@]}"
fi
if ((${#xpass_list[@]} > 0)); then
    echo
    echo "Unexpected PASSes (remove from EXPECTED_FAIL_LIST):"
    printf '  - %s\n' "${xpass_list[@]}"
fi
if ((${#xfail_list[@]} > 0)); then
    echo
    echo "Expected failures (known architectural gaps):"
    printf '  - %s\n' "${xfail_list[@]}"
fi
if ((${#skip_list[@]} > 0)); then
    echo
    echo "Skipped tests (known-unsupported):"
    printf '  - %s\n' "${skip_list[@]}"
fi
echo "Per-test logs: $log_dir"
echo "=================================================================="

# A run is green when every selected test is either in the passed list, in
# the skip/xfail buckets, or an unexpected pass (which only surfaces as a
# warning). Any NEW failure/timeout flips the run red.
if ((${#fail_list[@]} + ${#timeout_list[@]} > 0)); then
    exit 1
fi
exit 0
