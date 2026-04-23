# RTL file list: simulation-only replacements for Vivado IP.
#
# Do NOT add these to an FPGA synthesis flow; they model behaviour only
# (`i_rom` stores data in a 2-D reg array, `clk_wiz_0` passes the input
# clock through, etc).  The real board uses Vivado-generated IP.

sim/models/xilinx_compat.v
