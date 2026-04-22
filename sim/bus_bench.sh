#!/usr/bin/env bash
# Bus / memory microbenchmark driver.
#
# Builds sim/tests/bus_bench.S and runs it on the Icarus Verilog
# testbench.  Reads x28..x31 (per-kernel cycle counts) and reports
# cycles / iteration for RAM load, RAM store, and ROM .rodata load.
#
# Usage:
#   sim/bus_bench.sh
set -euo pipefail

script_dir=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd "$script_dir/.." && pwd)

toolbin="$repo_root/sw/tinyriscv/tests/toolchain/riscv64-unknown-elf-gcc-8.3.0-2020.04.0-x86_64-linux-ubuntu14/bin"
linker_script="$repo_root/sw/tinyriscv/tests/example/d.lds"
src_file="$repo_root/sim/tests/bus_bench.S"
timeout_val="${BUS_BENCH_TIMEOUT:-60s}"

# The benchmark runs 5000 iterations per kernel.  Hard-coded so we can
# pretty-print cycles/iter.  Keep in sync with ITER in bus_bench.S.
iter=5000

gcc_bin="$toolbin/riscv64-unknown-elf-gcc"
objcopy_bin="$toolbin/riscv64-unknown-elf-objcopy"

for required in "$gcc_bin" "$objcopy_bin" iverilog vvp timeout; do
    if ! command -v "$required" >/dev/null 2>&1; then
        echo "Missing required tool: $required" >&2
        exit 1
    fi
done

build_dir=$(mktemp -d "${TMPDIR:-/tmp}/riscv-cpu-bus-bench.XXXXXX")
trap 'rm -rf "$build_dir"' EXIT

echo "[1/4] Building bus microbenchmark..."
"$gcc_bin" -march=rv32im -mabi=ilp32 \
    -static -mcmodel=medany -fvisibility=hidden -nostdlib -nostartfiles \
    -T "$linker_script" "$src_file" \
    -o "$build_dir/bus_bench.elf"

echo "[2/4] Generating ROM image..."
"$objcopy_bin" -O verilog "$build_dir/bus_bench.elf" "$build_dir/bus_bench.verilog"

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
    "$repo_root/rtl/bus/axil_master_bridge.v"
    "$repo_root/rtl/bus/axil_slave_wrapper.v"
    "$repo_root/rtl/bus/axil_interconnect.v"
    "$repo_root/rtl/bus/axil_ifetch_bridge.v"
    "$repo_root/rtl/bus/icache.v"
    "$repo_root/rtl/memory/ram_c.v"
    "$repo_root/rtl/common/primitives/ram.v"
    "$repo_root/rtl/peripherals/uart/rxtx.v"
    "$repo_root/rtl/peripherals/timer/clnt.v"
    "$repo_root/rtl/memory/rodata.v"
    "$repo_root/rtl/peripherals/uart/cpu_uart.v"
    "$repo_root/rtl/common/primitives/fifo.v"
)

probe_tb="$build_dir/bus_probe.v"
cat >"$probe_tb" <<'EOF'
module bus_probe;
    initial begin
        wait (cpu_test.x26 == 32'b1);
        #1;
        $display("K1_RAM_LOAD  = %0d", cpu_test.x28);
        $display("K2_RAM_STORE = %0d", cpu_test.x29);
        $display("K3_ROM_LOAD  = %0d", cpu_test.x30);
        $display("TOTAL_CYCLES = %0d", cpu_test.x31);
    end
endmodule
EOF

echo "[3/4] Compiling testbench..."
iverilog -o "$build_dir/cpu_test.out" -s cpu_test -s bus_probe \
    "${rtl_files[@]}" "$probe_tb"

echo "[4/4] Running simulation..."
out=$(timeout "$timeout_val" vvp -n "$build_dir/cpu_test.out" \
         +IROM="$build_dir/bus_bench.verilog" 2>&1)

case "$out" in *TEST_PASS*) ;; *) echo "$out" >&2; echo "bus_bench FAILED" >&2; exit 1 ;; esac

parse() { grep -E "^$1" <<<"$out" | awk -F '= *' '{print $2}' | tr -d ' \r'; }

k1=$(parse K1_RAM_LOAD)
k2=$(parse K2_RAM_STORE)
k3=$(parse K3_ROM_LOAD)
total=$(parse TOTAL_CYCLES)

# Each kernel body is 3 instructions (mem + addi + bne) per iteration.
# cycles-per-iter = kernel_cycles / ITER.
cpi() { awk -v c="$1" -v n="$iter" 'BEGIN { printf "%.2f", c / n }'; }

printf '\n================================================================\n'
printf '  Bus / memory microbenchmark (ITER=%d per kernel)\n' "$iter"
printf '================================================================\n'
printf '  %-20s %12s %14s\n' "Kernel" "Cycles" "Cyc/iter"
printf '  %-20s %12s %14s\n' "--------------------" "------------" "--------------"
printf '  %-20s %12s %14s\n' "RAM load  (lw ram)"   "$k1" "$(cpi "$k1")"
printf '  %-20s %12s %14s\n' "RAM store (sw ram)"   "$k2" "$(cpi "$k2")"
printf '  %-20s %12s %14s\n' "ROM load  (lw .rodata)" "$k3" "$(cpi "$k3")"
printf '  %-20s %12s\n' "total run" "$total"
printf '================================================================\n'
echo "[bus_bench] PASS"
