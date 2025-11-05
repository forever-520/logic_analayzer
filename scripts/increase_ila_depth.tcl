# TCL 脚本：增大 ILA 采样深度
# 在 Vivado TCL Console 中运行

# 找到 ILA IP 核
set ila_cell [get_ips ila]

if {$ila_cell == ""} {
    puts "ERROR: ILA IP not found."
    return
}

puts "Found ILA IP: $ila_cell"

# 重新配置 ILA - 增大采样深度
set_property -dict [list \
    CONFIG.C_DATA_DEPTH {131072} \
] $ila_cell

# 重新生成 IP
generate_target all $ila_cell
synth_ip $ila_cell

puts "✅ ILA data depth updated to 131072 samples!"
puts "⏱️  Can now capture ~131K clock cycles (~2.62 ms @ 50MHz)"
puts ""
puts "UART transmission time: ~8.9M cycles (~178ms)"
puts "With 131K samples, you can capture ~1.5% of transmission"
puts ""
puts "💡 Recommendation:"
puts "   Use trigger on probe19 (tx_valid) rising edge"
puts "   This will capture the first ~15 bytes of data"
