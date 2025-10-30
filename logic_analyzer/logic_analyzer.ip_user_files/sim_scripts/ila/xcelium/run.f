-makelib xcelium_lib/xpm -sv \
  "F:/Xilinx/Vivado/2020.2/data/ip/xpm/xpm_cdc/hdl/xpm_cdc.sv" \
  "F:/Xilinx/Vivado/2020.2/data/ip/xpm/xpm_memory/hdl/xpm_memory.sv" \
-endlib
-makelib xcelium_lib/xpm \
  "F:/Xilinx/Vivado/2020.2/data/ip/xpm/xpm_VCOMP.vhd" \
-endlib
-makelib xcelium_lib/xil_defaultlib \
  "../../../../logic_analyzer.gen/sources_1/ip/ila/sim/ila.v" \
-endlib
-makelib xcelium_lib/xil_defaultlib \
  glbl.v
-endlib

