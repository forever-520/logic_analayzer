# TCL 脚本：更新 ILA IP 核配置
# 在 Vivado TCL Console 中运行此脚本

# 找到 ILA IP 核
set ila_cell [get_ips ila]

if {$ila_cell == ""} {
    puts "ERROR: ILA IP not found. Please create it first."
    return
}

puts "Found ILA IP: $ila_cell"

# 重新配置 ILA
set_property -dict [list \
    CONFIG.C_NUM_OF_PROBES {26} \
    CONFIG.C_PROBE0_WIDTH {8} \
    CONFIG.C_PROBE1_WIDTH {1} \
    CONFIG.C_PROBE2_WIDTH {11} \
    CONFIG.C_PROBE3_WIDTH {8} \
    CONFIG.C_PROBE4_WIDTH {1} \
    CONFIG.C_PROBE5_WIDTH {1} \
    CONFIG.C_PROBE6_WIDTH {1} \
    CONFIG.C_PROBE7_WIDTH {11} \
    CONFIG.C_PROBE8_WIDTH {1} \
    CONFIG.C_PROBE9_WIDTH {2} \
    CONFIG.C_PROBE10_WIDTH {3} \
    CONFIG.C_PROBE11_WIDTH {1} \
    CONFIG.C_PROBE12_WIDTH {1} \
    CONFIG.C_PROBE13_WIDTH {1} \
    CONFIG.C_PROBE14_WIDTH {1} \
    CONFIG.C_PROBE15_WIDTH {8} \
    CONFIG.C_PROBE16_WIDTH {1} \
    CONFIG.C_PROBE17_WIDTH {2} \
    CONFIG.C_PROBE18_WIDTH {8} \
    CONFIG.C_PROBE19_WIDTH {1} \
    CONFIG.C_PROBE20_WIDTH {1} \
    CONFIG.C_PROBE21_WIDTH {1} \
    CONFIG.C_PROBE22_WIDTH {11} \
    CONFIG.C_PROBE23_WIDTH {3} \
    CONFIG.C_PROBE24_WIDTH {1} \
    CONFIG.C_PROBE25_WIDTH {8} \
] $ila_cell

# 重新生成 IP
generate_target all $ila_cell
synth_ip $ila_cell

puts "ILA IP updated successfully with 26 probes!"
puts "New UART debug probes:"
puts "  probe18: tx_data [7:0]"
puts "  probe19: tx_valid"
puts "  probe20: tx_ready"
puts "  probe21: busy"
puts "  probe22: rd_addr [10:0]"
puts "  probe23: state [2:0]"
puts "  probe24: uart_tx"
puts "  probe25: rd_data [7:0]"
