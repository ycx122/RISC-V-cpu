#!/usr/bin/env bash
# Branch-predictor microbenchmark driver.
#
# Builds sim/tests/bpu_bench.S and runs it on the Icarus Verilog
# testbench.  Prints per-kernel cycle counts (x28..x31) and optional
# A/B comparison between the default build (BPU enabled) and a build
# compiled with -DBPU_DISABLE (prediction forced to not-taken, updates
# still exercised).
#
# Usage:
#   sim/bpu_bench.sh             # just run the default build
#   sim/bpu_bench.sh --compare   # run baseline (no BP) + default, tabulate
set -euo pipefail

mode=default
while (($# > 0)); do
    case "$1" in
        --compare) mode=compare; shift ;;
        --help|-h) sed -n '2,15p' "$0"; exit 0 ;;
        *) echo "Unknown option: $1" >&2; exit 1 ;;
    esac
done

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)
source "$repo_root/sim/scripts/common.sh"

linker_script="$repo_root/sw/tinyriscv/tests/example/d.lds"
src_file="$repo_root/sim/tests/bpu_bench.S"
timeout_val="${BPU_BENCH_TIMEOUT:-30s}"

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

build_dir=$(mktemp -d "${TMPDIR:-/tmp}/riscv-cpu-bpu-bench.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT

march=$(find_riscv_march rv32im)

echo "[1/4] Building BPU microbenchmark..."
"$gcc_bin" -march="$march" -mabi=ilp32 \
    -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles \
    -T "$linker_script" "$src_file" \
    -o "$build_dir/bpu_bench.elf"

echo "[2/4] Generating ROM image..."
"$objcopy_bin" -O verilog "$build_dir/bpu_bench.elf" "$build_dir/bpu_bench.verilog"
"$objdump_bin" --disassemble-all "$build_dir/bpu_bench.elf" >"$build_dir/bpu_bench.dump"

rtl_files=()
load_filelist "$repo_root/sim/filelist/tb_common.f"
load_filelist "$repo_root/sim/filelist/rtl_core.f"
load_filelist "$repo_root/sim/filelist/rtl_soc.f"
load_filelist "$repo_root/sim/filelist/sim_stubs.f"

probe_tb="$build_dir/bpu_probe.v"
cat >"$probe_tb" <<'EOF'
module bpu_probe;
    initial begin
        wait (cpu_test.x26 == 32'b1);
        #1;
        $display("K1_TIGHT_LOOP = %0d", cpu_test.x28);
        $display("K2_CALL_RET   = %0d", cpu_test.x29);
        $display("K3_NT_BRANCH  = %0d", cpu_test.x30);
        $display("TOTAL_CYCLES  = %0d", cpu_test.x31);
    end
endmodule
EOF

# Compile one variant and run the benchmark; echo stats on stdout.
# $1 = "on" | "off"   $2 = binary path
compile_and_run() {
    local which="$1" bin="$2"
    local defines=()
    if [[ "$which" == "off" ]]; then
        defines+=("-DBPU_DISABLE")
    fi
    iverilog "${defines[@]}" -o "$bin" -s cpu_test -s bpu_probe \
        "${rtl_files[@]}" "$probe_tb"
    timeout "$timeout_val" vvp -n "$bin" +IROM="$build_dir/bpu_bench.verilog" 2>&1
}

run_one() {
    local label="$1" which="$2"
    echo "[3/4] Compiling testbench (${label})..."
    local bin="$build_dir/cpu_test_${which}.out"
    echo "[4/4] Running simulation (${label})..."
    compile_and_run "$which" "$bin"
}

parse_cycles() {
    # $1 = captured sim output, $2 = line prefix (e.g. "K1_TIGHT_LOOP")
    grep -E "^$2" <<<"$1" | awk -F '= *' '{print $2}' | tr -d ' \r'
}

if [[ "$mode" == "compare" ]]; then
    off_out=$(run_one "BPU disabled (baseline)" off)
    on_out=$(run_one  "BPU enabled (default)"  on)

    case "$off_out" in *TEST_PASS*) ;; *) echo "$off_out" >&2; echo "baseline FAILED" >&2; exit 1 ;; esac
    case "$on_out"  in *TEST_PASS*) ;; *) echo "$on_out"  >&2; echo "default FAILED"  >&2; exit 1 ;; esac

    printf '\n========================================================\n'
    printf '  BPU A/B microbenchmark  (cycles, lower is better)\n'
    printf '========================================================\n'
    printf '  %-25s %10s %10s %10s\n' "Kernel" "No BP" "With BP" "Speedup"
    printf '  %-25s %10s %10s %10s\n' "-------------------------" "----------" "----------" "----------"
    for row in "K1_TIGHT_LOOP:10k addi+bne" \
               "K2_CALL_RET:5k jal+ret" \
               "K3_NT_BRANCH:10k NT-branch" \
               "TOTAL_CYCLES:total run"; do
        key="${row%%:*}"
        name="${row#*:}"
        b=$(parse_cycles "$off_out" "$key")
        w=$(parse_cycles "$on_out"  "$key")
        if [[ -n "$b" && -n "$w" && "$b" -gt 0 ]]; then
            speed=$(awk -v b="$b" -v w="$w" 'BEGIN{ printf "%.1f%%", (b-w)/b*100 }')
        else
            speed="?"
        fi
        printf '  %-25s %10s %10s %10s\n' "$name" "$b" "$w" "$speed"
    done
    printf '========================================================\n'
else
    out=$(run_one "BPU enabled (default)" on)
    case "$out" in *TEST_PASS*) ;; *) echo "$out" >&2; echo "bpu_bench FAILED" >&2; exit 1 ;; esac
    echo
    echo "[bpu_bench] x28 (tight-loop cycles, 10k iter)   = $(parse_cycles "$out" K1_TIGHT_LOOP)"
    echo "[bpu_bench] x29 (call+ret cycles, 5k pairs)     = $(parse_cycles "$out" K2_CALL_RET)"
    echo "[bpu_bench] x30 (NT-branch cycles, 10k iter)    = $(parse_cycles "$out" K3_NT_BRANCH)"
    echo "[bpu_bench] x31 (total from entry)              = $(parse_cycles "$out" TOTAL_CYCLES)"
    echo "[bpu_bench] PASS"
fi
