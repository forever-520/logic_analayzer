#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
UART 连续接收脚本 - 适配连续采样模式
接收多帧逻辑分析器数据
"""

import serial
import struct
import time
from datetime import datetime

def receive_continuous_frames(port='COM3', baudrate=115200, max_frames=10):
    """
    连续接收多帧逻辑分析器数据

    参数:
        port: 串口号 (Windows: COM3, Linux: /dev/ttyUSB0)
        baudrate: 波特率
        max_frames: 最大接收帧数（0=无限接收）
    """
    print(f"[{datetime.now().strftime('%H:%M:%S')}] Opening {port} at {baudrate} baud...")

    try:
        ser = serial.Serial(port, baudrate, timeout=2)
        print(f"✅ Serial port opened successfully")
        print(f"📡 Waiting for data frames... (Press Ctrl+C to stop)\n")

        frame_count = 0

        while True:
            # 等待帧头 0x55 0xAA
            while True:
                byte1 = ser.read(1)
                if not byte1:
                    continue

                if byte1 == b'\x55':
                    byte2 = ser.read(1)
                    if byte2 == b'\xAA':
                        print(f"\n{'='*60}")
                        print(f"📦 Frame #{frame_count + 1} detected at {datetime.now().strftime('%H:%M:%S.%f')[:-3]}")
                        print(f"{'='*60}")
                        break

            # 读取帧头（4 字节：LEN + TRIG）
            header = ser.read(4)
            if len(header) < 4:
                print(f"⚠️  Incomplete header, skipping...")
                continue

            frame_len = struct.unpack('<H', header[0:2])[0]  # 小端序
            trigger_idx = struct.unpack('<H', header[2:4])[0]

            print(f"  Header: 0x55 0xAA ✅")
            print(f"  Frame Length: {frame_len} bytes (0x{frame_len:04X})")
            print(f"  Trigger Index: {trigger_idx}")

            # 验证长度
            if frame_len != 2048:
                print(f"  ⚠️  Warning: Expected 2048 bytes, got {frame_len}")

            # 读取数据
            print(f"  📥 Receiving {frame_len} bytes...", end='', flush=True)
            data = ser.read(frame_len)

            if len(data) == frame_len:
                print(f" ✅ Done!")

                # 显示前 20 字节（十六进制）
                print(f"\n  First 20 bytes (HEX):")
                for i in range(min(20, len(data))):
                    print(f"  [{i:3d}] 0x{data[i]:02X}", end='')
                    if (i + 1) % 8 == 0:
                        print()  # 每 8 字节换行

                if len(data) > 20:
                    print(f"  ...")

                # 保存到文件
                filename = f"capture_frame_{frame_count + 1}_{datetime.now().strftime('%H%M%S')}.bin"
                with open(filename, 'wb') as f:
                    f.write(data)
                print(f"\n  💾 Saved to: {filename}")

                # 统计分析
                print(f"\n  📊 Statistics:")
                print(f"     Pre-trigger samples:  {trigger_idx}")
                print(f"     Post-trigger samples: {frame_len - trigger_idx}")

                # 检查数据模式（如果是测试信号）
                unique_values = len(set(data[:100]))  # 检查前 100 字节
                if unique_values < 20:
                    print(f"     Data pattern detected: ~{unique_values} unique values (may be test signal)")

                frame_count += 1

                # 达到最大帧数后退出
                if max_frames > 0 and frame_count >= max_frames:
                    print(f"\n✅ Received {frame_count} frames, stopping...")
                    break

            else:
                print(f" ❌ Failed!")
                print(f"     Expected {frame_len} bytes, got {len(data)}")

            # 短暂延时，避免丢失下一帧的帧头
            time.sleep(0.01)

    except KeyboardInterrupt:
        print(f"\n\n⏹️  Stopped by user")
        print(f"📊 Total frames received: {frame_count}")

    except serial.SerialException as e:
        print(f"\n❌ Serial port error: {e}")
        print(f"\n💡 Troubleshooting:")
        print(f"   - Check if {port} exists (Windows: Device Manager)")
        print(f"   - Try different port (COM4, COM5, etc.)")
        print(f"   - Install CH340 driver: http://www.wch.cn/downloads/CH341SER_EXE.html")

    finally:
        if 'ser' in locals() and ser.is_open:
            ser.close()
            print(f"🔌 Serial port closed")


if __name__ == '__main__':
    import sys

    # 根据你的系统修改端口号
    # Windows: 'COM3', 'COM4', 'COM5' 等
    # Linux: '/dev/ttyUSB0', '/dev/ttyUSB1' 等
    # macOS: '/dev/cu.usbserial-XXX'

    PORT = 'COM3'  # ← 修改为你的端口号

    # 最大接收帧数（0=无限接收，直到按 Ctrl+C）
    MAX_FRAMES = 10

    print("="*60)
    print(" UART 连续接收模式 - 逻辑分析器数据采集")
    print("="*60)
    print(f"🔧 Configuration:")
    print(f"   Port: {PORT}")
    print(f"   Baudrate: 115200")
    print(f"   Max frames: {MAX_FRAMES} (0 = unlimited)")
    print(f"   Frame format: [0x55 0xAA | LEN | TRIG | DATA]")
    print("="*60 + "\n")

    receive_continuous_frames(port=PORT, baudrate=115200, max_frames=MAX_FRAMES)

    print("\n" + "="*60)
    print("👋 Goodbye!")
    print("="*60)
