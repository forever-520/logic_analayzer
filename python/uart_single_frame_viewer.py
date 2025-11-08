#!/usr/bin/env python3
"""
UART逻辑分析仪 - 单帧波形显示
接收一帧数据并显示波形
"""

import serial
import struct
import matplotlib
matplotlib.rcParams['font.sans-serif'] = ['SimHei', 'Microsoft YaHei', 'Arial']
matplotlib.rcParams['axes.unicode_minus'] = False
import matplotlib.pyplot as plt
import numpy as np

# ========== 配置 ==========
SERIAL_PORT = 'COM11'  # 根据实际串口修改
BAUD_RATE = 115200
FRAME_HEADER = b'\x55\xaa'  # 帧头：0x55 0xAA (实际FPGA发送的)
FRAME_SIZE = 2048
CHANNEL_COUNT = 8

def receive_one_frame(ser):
    """接收一帧完整数据"""
    print("等待帧头 0x55 0xAA...")
    buffer = bytearray()

    # 查找帧头
    while True:
        byte = ser.read(1)
        if not byte:
            continue

        buffer.append(byte[0])

        # 检查最后两个字节是否为帧头
        if len(buffer) >= 2 and buffer[-2:] == FRAME_HEADER:
            print(f"✓ 找到帧头！位置: {len(buffer)-2}")
            break

    # 读取剩余数据：长度(2) + 采样率档位(1) + 触发索引(2) + 数据(2048) = 2053 字节
    print("正在接收数据...")
    remaining = ser.read(2053)

    if len(remaining) < 2053:
        print(f"❌ 数据不完整，只收到 {len(remaining)} 字节")
        return None

    # 解析
    frame_len = struct.unpack('<H', remaining[0:2])[0]
    rate_sel = remaining[2]
    trigger_idx = struct.unpack('<H', remaining[3:5])[0]
    payload = remaining[5:5+FRAME_SIZE]

    # 计算实际采样率
    div_factor = 1 << rate_sel
    sampling_rate = 32_000_000 / div_factor  # 基准32MHz

    print(f"✓ 帧长度: {frame_len}")
    print(f"✓ 采样率档位: {rate_sel} -> {sampling_rate/1e6:.3f} MHz (分频比 {div_factor})")
    print(f"✓ 触发位置: {trigger_idx}")
    print(f"✓ 数据负载: {len(payload)} 字节")

    return {
        'length': frame_len,
        'rate_sel': rate_sel,
        'sampling_rate': sampling_rate,
        'trigger_index': trigger_idx,
        'data': payload
    }

def plot_waveform(frame):
    """绘制8通道波形"""
    data = frame['data']
    trigger_idx_global = frame['trigger_index']  # 全局累计触发位置
    trigger_idx = trigger_idx_global % FRAME_SIZE  # 当前帧内的位置 (0-2047)
    sampling_rate = frame.get('sampling_rate', 32_000_000)  # 实际采样率(Hz)

    # 解析每个字节为8个通道
    channels = [[] for _ in range(CHANNEL_COUNT)]

    for byte_val in data:
        for ch in range(CHANNEL_COUNT):
            bit_val = (byte_val >> ch) & 0x01
            channels[ch].append(bit_val)

    # 创建图形
    rate_sel = frame.get('rate_sel', 0)
    fig, axes = plt.subplots(CHANNEL_COUNT, 1, figsize=(14, 10), sharex=True)
    fig.suptitle(f'逻辑分析仪波形 (8通道) - 采样率: {sampling_rate/1e6:.3f} MHz', fontsize=14)

    # 计算真实时间轴（单位：微秒）
    dt_us = 1e6 / sampling_rate  # 每个采样点的时间间隔(µs)
    time_axis = np.arange(len(channels[0])) * dt_us

    # 计算触发点对应的时间值
    trigger_time = trigger_idx * dt_us

    for i in range(CHANNEL_COUNT):
        axes[i].plot(time_axis, channels[i], 'b-', linewidth=1)
        axes[i].set_ylabel(f'CH{i}', fontsize=11, rotation=0, labelpad=20)
        axes[i].set_ylim(-0.2, 1.2)
        axes[i].grid(True, alpha=0.3)

        # 绘制触发点垂直线（使用时间坐标）
        axes[i].axvline(x=trigger_time, color='red', linestyle='--', linewidth=2, alpha=0.7,
                       label='Trigger' if i == 0 else '')

    # 在第一个通道显示图例
    axes[0].legend(loc='upper right', fontsize=10)

    axes[-1].set_xlabel('时间 (μs)', fontsize=11)
    plt.tight_layout()

    print("\n关闭图形窗口以退出...")
    plt.show()

if __name__ == '__main__':
    print("=" * 60)
    print("UART 逻辑分析仪 - 单帧波形显示")
    print("=" * 60)
    print(f"串口: {SERIAL_PORT}")
    print(f"波特率: {BAUD_RATE}")
    print("=" * 60)

    try:
        ser = serial.Serial(SERIAL_PORT, BAUD_RATE, timeout=2)
        print(f"✓ 串口打开成功\n")

        # 接收一帧
        frame = receive_one_frame(ser)

        if frame:
            print("\n" + "=" * 60)
            print("开始绘制波形...")
            plot_waveform(frame)
        else:
            print("❌ 未能接收到完整帧")

        ser.close()
        print("串口已关闭")

    except serial.SerialException as e:
        print(f"❌ 串口错误: {e}")
        print(f"提示: 请检查串口号 {SERIAL_PORT} 是否正确")
    except KeyboardInterrupt:
        print("\n用户中断")
    except Exception as e:
        print(f"❌ 错误: {e}")
        import traceback
        traceback.print_exc()
