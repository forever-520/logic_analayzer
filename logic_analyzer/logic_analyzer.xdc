# Logic Analyzer top-level constraints (initial bring-up)
# Board: custom (pins taken from your pin tables)
# Clock: PL_GCLK @ 50MHz on N18

## Clock -----------------------------------------------------------------
create_clock -name sys_clk -period 20.000 [get_ports sys_clk]
set_property PACKAGE_PIN N18 [get_ports sys_clk]
set_property IOSTANDARD LVCMOS33 [get_ports sys_clk]

## Reset (active-low) -----------------------------------------------------
# Tie high by internal pull-up for now (no external pin used)
set_property PULLUP true [get_ports sys_rst_n]
set_property IOSTANDARD LVCMOS33 [get_ports sys_rst_n]

## Push Buttons (active-low into debounce) --------------------------------
# PL_KEY1..4 used as control keys
set_property PACKAGE_PIN G19 [get_ports btn_trigger_en]
set_property PACKAGE_PIN G20 [get_ports btn_channel_select]
set_property PACKAGE_PIN H15 [get_ports btn_type_select]
set_property PACKAGE_PIN G15 [get_ports btn_trigger_mode]
set_property IOSTANDARD LVCMOS33 [get_ports {btn_trigger_en btn_channel_select btn_type_select btn_trigger_mode}]
set_property PULLUP true [get_ports {btn_trigger_en btn_channel_select btn_type_select btn_trigger_mode}]

## Probe inputs (8 channels) ----------------------------------------------
# Use one column of J24 (odd-numbered pins), all on the same header column:
#  J24-7  -> D8
#  J24-9  -> W6
#  J24-11 -> W8
#  J24-13 -> W9
#  J24-17 -> V10
#  J24-19 -> Y13
#  J24-21 -> Y6
#  J24-23 -> Y8
set_property PACKAGE_PIN D8  [get_ports {probe_signals[0]}]   ;# J24-7
set_property PACKAGE_PIN W6  [get_ports {probe_signals[1]}]   ;# J24-9
set_property PACKAGE_PIN W8  [get_ports {probe_signals[2]}]   ;# J24-11
set_property PACKAGE_PIN W9  [get_ports {probe_signals[3]}]   ;# J24-13
set_property PACKAGE_PIN V10 [get_ports {probe_signals[4]}]   ;# J24-17
set_property PACKAGE_PIN Y13 [get_ports {probe_signals[5]}]   ;# J24-19
set_property PACKAGE_PIN Y6  [get_ports {probe_signals[6]}]   ;# J24-21
set_property PACKAGE_PIN Y8  [get_ports {probe_signals[7]}]   ;# J24-23
set_property IOSTANDARD LVCMOS33 [get_ports {probe_signals[*]}]
# Optional: async inputs to synchronizer, cut timing from pads to first FF
set_false_path -from [get_ports {probe_signals[*]}]

## Test generator switches (optional) -------------------------------------
# If no physical switches yet, use internal pulls to set defaults:
set_property PULLUP   true [get_ports sw_test_enable]        ;# default enable
set_property PULLDOWN true [get_ports {sw_test_pattern[0]}]  ;# pattern = 2'b00
set_property PULLDOWN true [get_ports {sw_test_pattern[1]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw_test_enable sw_test_pattern[*]}]

## LEDs (optional, add when you know LED pins) ----------------------------
# Example placeholders (commented):
# set_property PACKAGE_PIN <P_LED0> [get_ports led_capturing]
# set_property PACKAGE_PIN <P_LED1> [get_ports led_triggered]
# set_property PACKAGE_PIN <P_LED2> [get_ports led_done]
# set_property IOSTANDARD LVCMOS33 [get_ports {led_capturing led_triggered led_done}]

## Notes ------------------------------------------------------------------
# - la_trigger_index is kept internal/ILA only; no package pins are assigned.
# - Complete the remaining probe_signals[*] LOCs per your J24 table before using external probes.
