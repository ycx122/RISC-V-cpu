# RTL file list: SoC top-level, AXI4-Lite interconnect, memories, peripherals.
#
# See sim/filelist/rtl_core.f for the shared syntax rules.  Synthesisable
# blocks only -- simulation-only stubs belong in sim_stubs.f, and the
# testbench top itself lives in tb_common.f.

rtl/soc/cpu_soc.v

# AXI4-Lite bus
rtl/bus/axil_master_bridge.v
rtl/bus/axil_slave_wrapper.v
rtl/bus/axil_interconnect.v
rtl/bus/axil_ifetch_bridge.v
rtl/bus/icache.v

# Memories
rtl/memory/ram_c.v
rtl/memory/rodata.v
rtl/common/primitives/ram.v
rtl/common/primitives/fifo.v

# Peripherals
rtl/peripherals/uart/rxtx.v
rtl/peripherals/uart/cpu_uart.v
rtl/peripherals/timer/clnt.v
rtl/peripherals/plic/plic.v
