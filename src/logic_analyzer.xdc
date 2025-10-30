# Logic Analyzer top-level constraints
# Device: xc7z010clg400-2 (Zynq-7000) — adjust pins if your board differs.

## Clock -----------------------------------------------------------------
create_clock -period 20.000 -name sys_clk [get_ports sys_clk]
set_property PACKAGE_PIN N18 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]

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

## Test generator switches (optional) -------------------------------------
# Map test-source switches to the same header column. Provide default pulls.
set_property PULLUP true [get_ports sw_test_enable]
set_property PULLDOWN true [get_ports {sw_test_pattern[0]}]
set_property PULLDOWN true [get_ports {sw_test_pattern[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_test_enable {sw_test_pattern[*]}}]

## Notes ------------------------------------------------------------------
# - Adjust LOCs if these pins conflict with board peripherals.
# - la_trigger_index and LEDs remain internal; no pins are assigned.

set_property PACKAGE_PIN T14 [get_ports {probe_signals[6]}]
set_property PACKAGE_PIN T15 [get_ports {probe_signals[7]}]
set_property PACKAGE_PIN T12 [get_ports {probe_signals[2]}]
set_property PACKAGE_PIN U12 [get_ports {probe_signals[3]}]
set_property PACKAGE_PIN U13 [get_ports {probe_signals[4]}]
set_property PACKAGE_PIN V13 [get_ports {probe_signals[5]}]

set_property PACKAGE_PIN P16 [get_ports {sw_test_pattern[1]}]
set_property PACKAGE_PIN T19 [get_ports {sw_test_pattern[0]}]

set_property PACKAGE_PIN P15 [get_ports sw_test_enable]
set_property C_CLK_INPUT_FREQ_HZ 300000000 [get_debug_cores dbg_hub]
set_property C_ENABLE_CLK_DIVIDER false [get_debug_cores dbg_hub]
set_property C_USER_SCAN_CHAIN 1 [get_debug_cores dbg_hub]
connect_debug_port dbg_hub/clk [get_nets sys_clk_IBUF_BUFG]
