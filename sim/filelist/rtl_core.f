# RTL file list: CPU core.
#
# One Verilog source path per line, relative to the repo root.
# Blank lines and `#`-prefixed comments are ignored.
#
# Used by sim/smoke.sh, sim/run_isa.sh, sim/smoke_mi.sh, sim/bpu_bench.sh,
# sim/bus_bench.sh, sim/run_dhrystone.sh and scripts/lint.sh via the shared
# `load_filelist` helper in sim/scripts/common.sh.
#
# Order is top-down (cpu_jh first, submodules after) so tools that warn on
# late definitions stay quiet.  Do not add SoC / bus / memory / peripheral
# files here -- those live in rtl_soc.f.

rtl/core/cpu_jh.v
rtl/core/pipeline_regs.v
rtl/core/hazard_ctrl.v
rtl/core/flush_ctrl.v
rtl/core/stop_cache.v
rtl/core/branch_unit.v
rtl/core/forward_mux.v
rtl/core/mem_ctrl.v
rtl/core/pc.v
rtl/core/branch_pred.v
rtl/core/id.v
rtl/core/alu.v
rtl/core/csr_reg.v
rtl/core/regfile.v
rtl/core/ju.v
rtl/core/im2op.v
rtl/core/otof1.v
rtl/core/mul_div.v
rtl/core/div_gen.v
rtl/core/mul.v
