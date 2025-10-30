vlib questa_lib/work
vlib questa_lib/msim

vlib questa_lib/msim/xpm
vlib questa_lib/msim/xil_defaultlib

vmap xpm questa_lib/msim/xpm
vmap xil_defaultlib questa_lib/msim/xil_defaultlib

vlog -work xpm  -sv "+incdir+../../../../logic_analyzer.gen/sources_1/ip/ila/hdl/verilog" \
"F:/Xilinx/Vivado/2020.2/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
"F:/Xilinx/Vivado/2020.2/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \

vcom -work xpm  -93 \
"F:/Xilinx/Vivado/2020.2/data/ip/xpm/xpm_VCOMP.vhd" \

vlog -work xil_defaultlib  "+incdir+../../../../logic_analyzer.gen/sources_1/ip/ila/hdl/verilog" \
"../../../../logic_analyzer.gen/sources_1/ip/ila/sim/ila.v" \

vlog -work xil_defaultlib \
"glbl.v"

