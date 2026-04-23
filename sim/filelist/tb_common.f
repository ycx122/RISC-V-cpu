# RTL file list: shared testbench top.
#
# Kept separate from rtl_core.f / rtl_soc.f so the static lint flow
# (scripts/lint.sh) can exclude the testbench -- lint's top module is
# `cpu_soc`, and pulling in sim/tb/cpu_test.v would add a second
# conflicting top.

sim/tb/cpu_test.v
