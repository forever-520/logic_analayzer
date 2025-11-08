#!/usr/bin/env python3
"""
UART逻辑分析仪 - 连续实时波形显示
接收多帧数据并实时更新波形显示
"""

import serial
import struct
import matplotlib
matplotlib.rcParams['font.sans-serif'] = ['SimHei', 'Microsoft YaHei', 'Arial']
matplotlib.rcParams['axes.unicode_minus'] = False
import matplotlib.pyplot as plt
import matplotlib.animation as animation
import numpy as np
from collections import deque
from datetime import datetime

# ========== 配置 ==========
SERIAL_PORT = 'COM11'  # 根据实际串口修改
BAUD_RATE = 115200
FRAME_HEADER = b'\x55\xaa'  # 帧头：0x55 0xAA (修正实际FPGA发送的)
FRAME_SIZE = 2048
CHANNEL_COUNT = 8
MAX_FRAMES = 5  # 屏幕显示最多保留的帧数
UPDATE_INTERVAL = 100  # 动画更新间隔(ms)

class ContinuousViewer:
    """连续波形查看器"""

    def __init__(self, serial_port, baud_rate):
        self.ser = serial.Serial(serial_port, baud_rate, timeout=0.5)
        self.frame_queue = deque(maxlen=MAX_FRAMES)
        self.running = True
        self.frame_count = 0
        self.last_trigger_time = None

        # 创建图形
        self.fig, self.axes = plt.subplots(CHANNEL_COUNT, 1, figsize=(14, 10), sharex=True)
        self.fig.suptitle('逻辑分析仪实时波形 (连续模式)', fontsize=14)

        # 当前采样率
        self.current_sampling_rate = 32_000_000  # 默认32MHz

        # 初始化每个通道的绘图对象
        self.lines = []
        self.trigger_lines = []

        for i in range(CHANNEL_COUNT):
            # 波形线
            line, = self.axes[i].plot([], [], 'b-', linewidth=1)
            self.lines.append(line)

            # 触发线
            trigger_line = self.axes[i].axvline(x=0, color='red', linestyle='--',
                                               linewidth=2, alpha=0.7, visible=False)
            self.trigger_lines.append(trigger_line)

            self.axes[i].set_ylabel(f'CH{i}', fontsize=11, rotation=0, labelpad=20)
            self.axes[i].set_ylim(-0.2, 1.2)
            self.axes[i].grid(True, alpha=0.3)

        # 添加图例到第一个通道
        self.axes[0].legend(['波形', '触发点'], loc='upper right', fontsize=10)
        self.axes[-1].set_xlabel('时间 (μs)', fontsize=11)

        # 状态文本
        self.status_text = self.fig.text(0.02, 0.98, '', ha='left', va='top',
                                         fontsize=10, family='monospace')

        plt.tight_layout()

        print(f"✓ 串口打开: {serial_port} @ {baud_rate}")
        print("=" * 60)

    def receive_one_frame(self):
        """接收一帧完整数据"""
        buffer = bytearray()

        # 查找帧头（最多等待5秒）
        timeout_count = 0
        while timeout_count < 100:  # 100 * 50ms = 5s
            byte = self.ser.read(1)
            if not byte:
                timeout_count += 1
                continue

            buffer.append(byte[0])

            # 检查最后两个字节是否为帧头
            if len(buffer) >= 2 and buffer[-2:] == FRAME_HEADER:
                break

        if timeout_count >= 100:
            return None

        # 读取剩余数据：长度(2) + 采样率档位(1) + 触发索引(2) + 数据(2048) = 2053 字节
        remaining = self.ser.read(2053)

        if len(remaining) < 2053:
            print(f"⚠ 数据不完整: {len(remaining)}/2053 字节")
            return None

        # 解析
        frame_len = struct.unpack('<H', remaining[0:2])[0]
        rate_sel = remaining[2]
        trigger_idx = struct.unpack('<H', remaining[3:5])[0]
        payload = remaining[5:5+FRAME_SIZE]

        # 计算实际采样率
        div_factor = 1 << rate_sel
        sampling_rate = 32_000_000 / div_factor  # 基准32MHz

        return {
            'length': frame_len,
            'rate_sel': rate_sel,
            'sampling_rate': sampling_rate,
            'trigger_index': trigger_idx,
            'data': payload,
            'timestamp': datetime.now()
        }

    def parse_frame_to_channels(self, frame_data):
        """将帧数据解析为8个通道"""
        channels = [[] for _ in range(CHANNEL_COUNT)]

        for byte_val in frame_data:
            for ch in range(CHANNEL_COUNT):
                bit_val = (byte_val >> ch) & 0x01
                channels[ch].append(bit_val)

        return channels

    def update_plot(self, frame_num):
        """动画更新回调"""
        if not self.running:
            return self.lines + self.trigger_lines + [self.status_text]

        # 尝试接收新帧
        new_frame = self.receive_one_frame()

        if new_frame:
            self.frame_queue.append(new_frame)
            self.frame_count += 1
            self.last_trigger_time = new_frame['timestamp']

            # 计算触发间隔
            if len(self.frame_queue) >= 2:
                time_diff = (self.frame_queue[-1]['timestamp'] -
                           self.frame_queue[-2]['timestamp']).total_seconds()
                interval_info = f" | 间隔: {time_diff:.3f}s"
            else:
                interval_info = ""

            print(f"✓ 帧 {self.frame_count}: 触发@{new_frame['trigger_index']:4d}{interval_info}")

        # 如果有数据，绘制最新一帧
        if self.frame_queue:
            latest_frame = self.frame_queue[-1]
            channels = self.parse_frame_to_channels(latest_frame['data'])
            trigger_idx = latest_frame['trigger_index'] % FRAME_SIZE

            # 更新采样率（如果有变化）
            if 'sampling_rate' in latest_frame:
                self.current_sampling_rate = latest_frame['sampling_rate']

            # 计算真实时间轴（单位：微秒）
            dt_us = 1e6 / self.current_sampling_rate
            time_axis = np.arange(len(channels[0])) * dt_us
            trigger_time = trigger_idx * dt_us

            for i in range(CHANNEL_COUNT):
                # 更新波形
                self.lines[i].set_data(time_axis, channels[i])

                # 更新触发线（使用时间坐标）
                self.trigger_lines[i].set_xdata([trigger_time])
                self.trigger_lines[i].set_visible(True)

            # 更新坐标轴范围
            self.axes[-1].set_xlim(0, time_axis[-1])

            # 更新状态文本和标题
            rate_str = f"{self.current_sampling_rate/1e6:.3f} MHz"
            self.fig.suptitle(f'逻辑分析仪实时波形 (连续模式) - 采样率: {rate_str}', fontsize=14)

            status = f"帧数: {self.frame_count} | 队列: {len(self.frame_queue)}/{MAX_FRAMES}"
            if self.last_trigger_time:
                status += f" | 最后触发: {self.last_trigger_time.strftime('%H:%M:%S.%f')[:-3]}"
            self.status_text.set_text(status)

        return self.lines + self.trigger_lines + [self.status_text]

    def start(self):
        """启动实时显示"""
        print("开始连续采集...")
        print("关闭窗口以停止\n")

        # 创建动画
        self.anim = animation.FuncAnimation(
            self.fig,
            self.update_plot,
            interval=UPDATE_INTERVAL,
            blit=True,
            cache_frame_data=False
        )

        try:
            plt.show()
        except KeyboardInterrupt:
            print("\n用户中断")
        finally:
            self.stop()

    def stop(self):
        """停止采集并关闭串口"""
        self.running = False
        if hasattr(self, 'anim'):
            self.anim.event_source.stop()
        self.ser.close()
        print(f"\n总计接收 {self.frame_count} 帧")
        print("串口已关闭")

if __name__ == '__main__':
    print("=" * 60)
    print("UART 逻辑分析仪 - 连续实时波形显示")
    print("=" * 60)
    print(f"串口: {SERIAL_PORT}")
    print(f"波特率: {BAUD_RATE}")
    print(f"刷新间隔: {UPDATE_INTERVAL}ms")
    print(f"帧队列深度: {MAX_FRAMES}")
    print("=" * 60)

    try:
        viewer = ContinuousViewer(SERIAL_PORT, BAUD_RATE)
        viewer.start()
    except serial.SerialException as e:
        print(f"❌ 串口错误: {e}")
        print(f"提示: 请检查串口号 {SERIAL_PORT} 是否正确")
    except KeyboardInterrupt:
        print("\n用户中断")
    except Exception as e:
        print(f"❌ 错误: {e}")
        import traceback
        traceback.print_exc()
