# Logic Analyzer top-level constraints
# Device: xc7z010clg400-2 (Zynq-7000) — adjust pins if your board differs.

## Clock -----------------------------------------------------------------
# 主时钟：50MHz系统时钟
create_clock -period 20.000 -name sys_clk [get_ports sys_clk]
set_property PACKAGE_PIN N18 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]

# PLL生成的32MHz时钟（由Vivado自动约束，这里仅作参考）
# create_generated_clock -name clk_32m -source [get_pins u_pll/sys_clk] \
#     -multiply_by 20 -divide_by 31.25 [get_pins u_pll/clk_out1]

# 异步时钟组：sys_clk 和 clk_32m 彼此异步
set_clock_groups -asynchronous \
    -group [get_clocks -include_generated_clocks sys_clk] \
    -group [get_clocks -of_objects [get_pins u_pll/clk_out1]]

# 允许sys_clk同时用于PLL输入和其他逻辑（抑制8-5535警告）
# 注意：确保所有使用sys_clk的逻辑与PLL输出的时钟域正确隔离
set_property ALLOW_COMBINATORIAL_LOOPS TRUE [get_nets sys_clk_IBUF]

## Reset (active-low) -----------------------------------------------------
# External reset pin (active-low). Kept pulled-up when not driven.
set_property PACKAGE_PIN P19 [get_ports sys_rst_n]
set_property PULLUP true [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n]

## Push Buttons (active-low into debounce) --------------------------------
set_property PACKAGE_PIN G19 [get_ports btn_trigger_en]
set_property PACKAGE_PIN G20 [get_ports btn_channel_select]
set_property PACKAGE_PIN H15 [get_ports btn_type_select]
set_property PACKAGE_PIN G15 [get_ports btn_trigger_mode]
set_property IOSTANDARD LVCMOS33 [get_ports btn_trigger_en]
set_property IOSTANDARD LVCMOS33 [get_ports btn_channel_select]
set_property IOSTANDARD LVCMOS33 [get_ports btn_type_select]
set_property IOSTANDARD LVCMOS33 [get_ports btn_trigger_mode]
set_property PULLUP true [get_ports btn_trigger_en]
set_property PULLUP true [get_ports btn_channel_select]
set_property PULLUP true [get_ports btn_type_select]
set_property PULLUP true [get_ports btn_trigger_mode]

## Probe inputs (8 channels) ----------------------------------------------
# Choose one column of J25 external header (3.3V bank). Adjust if needed.
set_property PACKAGE_PIN T11 [get_ports {probe_signals[0]}]
set_property PACKAGE_PIN T10 [get_ports {probe_signals[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {probe_signals[*]}]
# Optional: async inputs to synchronizer, cut timing from pads to first FF
set_false_path -from [get_ports {probe_signals[*]}]

## Notes ------------------------------------------------------------------
# - Adjust LOCs if these pins conflict with board peripherals.
# - la_trigger_index and LEDs remain internal; no pins are assigned.

set_property PACKAGE_PIN T14 [get_ports {probe_signals[6]}]
set_property PACKAGE_PIN T15 [get_ports {probe_signals[7]}]
set_property PACKAGE_PIN T12 [get_ports {probe_signals[2]}]
set_property PACKAGE_PIN U12 [get_ports {probe_signals[3]}]
set_property PACKAGE_PIN U13 [get_ports {probe_signals[4]}]
set_property PACKAGE_PIN V13 [get_ports {probe_signals[5]}]

## UART TX (for data export to PC) -----------------------------------------
# Connect to CH340 RX pin or FPGA board's UART TX pin
# Adjust pin number according to your board schematic
set_property PACKAGE_PIN V18 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

## ILA Debug Hub Configuration ----------------------------------------------
# ILA调试核心配置（这些约束会在综合时自动生成，注释掉避免冲突）
# set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
# set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
# set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
# connect_debug_port dbg_hub/clk [get_nets sys_clk_IBUF_BUFG]
