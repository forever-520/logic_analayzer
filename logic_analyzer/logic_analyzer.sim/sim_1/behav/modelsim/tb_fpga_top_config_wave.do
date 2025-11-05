######################################################################
#
# File name : tb_fpga_top_config_wave.do
# Created on: Thu Oct 23 21:49:35 +0800 2025
#
# Modified to include BRAM and UART signals
#
######################################################################

# 添加顶层测试平台信号
add wave -divider "Clock & Reset"
add wave -format Logic /tb_fpga_top_config/sys_clk
add wave -format Logic /tb_fpga_top_config/sys_rst_n

# 探针输入信号
add wave -divider "Probe Input Signals"
add wave -format Literal -radix hexadecimal /tb_fpga_top_config/probe_signals
add wave -format Logic /tb_fpga_top_config/probe_signals(0)
add wave -format Logic /tb_fpga_top_config/probe_signals(1)
add wave -format Logic /tb_fpga_top_config/probe_signals(2)
add wave -format Logic /tb_fpga_top_config/probe_signals(3)
add wave -format Logic /tb_fpga_top_config/probe_signals(4)
add wave -format Logic /tb_fpga_top_config/probe_signals(5)
add wave -format Logic /tb_fpga_top_config/probe_signals(6)
add wave -format Logic /tb_fpga_top_config/probe_signals(7)

# 同步后的探针信号
add wave -divider "Synchronized Signals"
add wave -format Literal -radix hexadecimal /tb_fpga_top_config/u_dut/probe_sync
add wave -format Literal -radix hexadecimal /tb_fpga_top_config/u_dut/sample_data

# 按键控制信号
add wave -divider "Button Controls"
add wave -format Logic /tb_fpga_top_config/btn_trigger_en
add wave -format Logic /tb_fpga_top_config/btn_channel_select
add wave -format Logic /tb_fpga_top_config/btn_type_select
add wave -format Logic /tb_fpga_top_config/btn_trigger_mode

# 逻辑分析仪核心状态
add wave -divider "Logic Analyzer Core Status"
add wave -format Logic /tb_fpga_top_config/u_dut/capturing
add wave -format Logic /tb_fpga_top_config/u_dut/triggered
add wave -format Logic /tb_fpga_top_config/u_dut/capture_done
add wave -format Literal -radix unsigned /tb_fpga_top_config/u_dut/trigger_index

# 触发配置
add wave -divider "Trigger Configuration"
add wave -format Logic /tb_fpga_top_config/u_dut/trigger_enable_sync
add wave -format Literal -radix unsigned /tb_fpga_top_config/u_dut/trigger_mode_sel
add wave -format Literal -radix unsigned /tb_fpga_top_config/u_dut/config_channel_idx
add wave -format Literal -radix binary /tb_fpga_top_config/u_dut/trigger_mask
add wave -format Literal -radix binary /tb_fpga_top_config/u_dut/edge_trigger_mode
add wave -format Literal -radix binary /tb_fpga_top_config/u_dut/trigger_type

# BRAM 写入信号
add wave -divider "BRAM Write Signals"
add wave -format Logic /tb_fpga_top_config/u_dut/wr_en
add wave -format Literal -radix unsigned /tb_fpga_top_config/u_dut/wr_addr
add wave -format Literal -radix hexadecimal /tb_fpga_top_config/u_dut/wr_data

# BRAM 存储器内容（前64个地址）
add wave -divider "BRAM Memory Contents"
add wave -format Literal -radix hexadecimal /tb_fpga_top_config/u_dut/u_sample_buffer/ram(0)
add wave -format Literal -radix hexadecimal /tb_fpga_top_config/u_dut/u_sample_buffer/ram(1)
add wave -format Literal -radix hexadecimal /tb_fpga_top_config/u_dut/u_sample_buffer/ram(2)
add wave -format Literal -radix hexadecimal /tb_fpga_top_config/u_dut/u_sample_buffer/ram(3)

# UART 信号
add wave -divider "UART Signals"
add wave -format Logic /tb_fpga_top_config/uart_tx
add wave -format Logic /tb_fpga_top_config/u_dut/uart_start
add wave -format Logic /tb_fpga_top_config/u_dut/uart_busy
add wave -format Logic /tb_fpga_top_config/u_dut/uart_done
add wave -format Literal -radix unsigned /tb_fpga_top_config/u_dut/rd_addr
add wave -format Literal -radix hexadecimal /tb_fpga_top_config/u_dut/rd_data

# UART Streamer 状态机
add wave -divider "UART Streamer State"
add wave -format Literal -radix unsigned /tb_fpga_top_config/u_dut/u_uart_streamer/state
add wave -format Literal -radix unsigned /tb_fpga_top_config/u_dut/u_uart_streamer/bytes_sent
add wave -format Literal -radix hexadecimal /tb_fpga_top_config/u_dut/u_uart_streamer/tx_data
add wave -format Logic /tb_fpga_top_config/u_dut/u_uart_streamer/tx_valid
add wave -format Logic /tb_fpga_top_config/u_dut/u_uart_streamer/tx_ready

add wave /glbl/GSR
