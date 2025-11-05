# 📡 UART 调试使用指南

## 🎯 两种调试方法对比

### 方法 1：使用 ILA（集成逻辑分析仪）调试内部信号

**优点**：
- ✅ 可以看到 FPGA 内部所有信号（tx_data, tx_valid, state 等）
- ✅ 不需要外部硬件（CH340）
- ✅ 适合调试 UART 模块本身的逻辑问题
- ✅ 可以精确看到每个时钟周期的信号变化

**缺点**：
- ❌ 看不到实际串口输出是否正确
- ❌ 无法验证与上位机的完整通信流程
- ❌ 需要在 Vivado 中添加 ILA IP 核

**适用场景**：
- 调试 UART 发送时序是否正确
- 检查状态机跳转逻辑
- 验证 tx_data 的值是否符合预期

---

### 方法 2：使用 CH340 + 上位机接收真实数据 ⭐ **推荐用于最终验证**

**优点**：
- ✅ 验证完整的端到端通信
- ✅ 可以直接看到接收到的字节数据
- ✅ 能发现波特率、电平等硬件问题
- ✅ 符合实际应用场景

**缺点**：
- ❌ 需要 CH340 硬件模块
- ❌ 需要编写上位机接收程序
- ❌ 调试硬件连接问题比较麻烦

**适用场景**：
- 最终功能验证
- 检查实际通信是否正常
- 验证上位机软件

---

## 🔧 方法 1：使用 ILA 调试

### 步骤 1：在 Vivado 中添加 ILA

在 `fpga_top.v` 中实例化 ILA，监控关键信号：

```verilog
// 在 fpga_top.v 中添加（综合模式下）
`ifndef SIMULATION
    ila_0 u_ila (
        .clk(sys_clk),
        .probe0(u_uart_streamer.tx_data),      // [7:0] 发送的字节
        .probe1(u_uart_streamer.tx_valid),     // [0:0] 发送请求
        .probe2(u_uart_streamer.tx_ready),     // [0:0] 空闲标志
        .probe3(u_uart_streamer.busy),         // [0:0] 发送忙
        .probe4(u_uart_streamer.rd_addr),      // [10:0] BRAM 读地址
        .probe5(uart_tx)                       // [0:0] 实际 TX 信号
    );
`endif
```

### 步骤 2：配置 ILA 触发条件

在 Vivado Hardware Manager 中：
1. 触发条件：`u_uart_streamer.busy == 1` （开始发送）
2. 捕获深度：8192 samples（足够看到多个字节）
3. 运行并触发

### 步骤 3：分析波形

查看：
- `tx_data` 的值是否符合预期（头部应该是 0x55, 0xAA, 0x00, 0x08...）
- `tx_valid` 和 `tx_ready` 的握手时序
- `rd_addr` 是否从 0 递增到 2047

---

## 📡 方法 2：使用 CH340 + 上位机接收（推荐）

### 硬件连接

```
┌─────────────────┐         ┌─────────────┐         ┌──────────┐
│ FPGA 开发板     │         │ CH340 模块  │   USB   │ 电脑端   │
│                 │         │             │ ─────── │          │
│  uart_tx (TX)   │────────▶│ RXD         │         │  COM3    │
│  GND            │────────▶│ GND         │         │          │
└─────────────────┘         └─────────────┘         └──────────┘

注意：FPGA TX 连接到 CH340 RX
     波特率必须匹配：115200
```

**管脚连接示例（根据你的开发板调整）**：
- FPGA TX → CH340 RXD
- FPGA GND → CH340 GND
- CH340 VCC → 3.3V 或 5V（查看模块规格）

---

### 电脑端操作

#### 选项 A：使用串口调试助手（最简单）

1. **下载串口调试工具**：
   - Windows: [SSCOM](https://www.sscom.net/) 或 PuTTY
   - 全平台: [CoolTerm](https://freeware.the-meiers.org/)

2. **配置串口参数**：
   ```
   波特率：115200
   数据位：8
   停止位：1
   校验位：无
   流控：无
   ```

3. **打开串口并观察**：
   - 按下 FPGA 的 RUN 按钮触发采样
   - 采样完成后，串口助手应该接收到 2054 字节
   - 查看前 6 字节：`55 AA 00 08 XX XX`（XX 是触发索引）

#### 选项 B：使用 Python 脚本（推荐，功能强大）

创建 `uart_receiver.py`：

```python
import serial
import struct

def receive_logic_analyzer_data(port='COM3', baudrate=115200):
    """接收逻辑分析仪数据"""
    print(f"Opening {port} at {baudrate} baud...")
    ser = serial.Serial(port, baudrate, timeout=5)

    # 等待帧头 0x55 0xAA
    print("Waiting for frame header (0x55 0xAA)...")
    while True:
        byte1 = ser.read(1)
        if byte1 == b'\x55':
            byte2 = ser.read(1)
            if byte2 == b'\xAA':
                print("✅ Header found: 0x55 0xAA")
                break

    # 读取帧头（4 字节：LEN + TRIG）
    header = ser.read(4)
    frame_len = struct.unpack('<H', header[0:2])[0]  # 小端序
    trigger_idx = struct.unpack('<H', header[2:4])[0]

    print(f"Frame Length: {frame_len} (0x{frame_len:04X})")
    print(f"Trigger Index: {trigger_idx}")

    # 读取数据
    print(f"Receiving {frame_len} bytes...")
    data = ser.read(frame_len)

    if len(data) == frame_len:
        print(f"✅ Received {len(data)} bytes successfully!")

        # 保存到文件
        with open('capture.bin', 'wb') as f:
            f.write(data)
        print("Data saved to capture.bin")

        # 显示前 20 字节（十六进制）
        print("\nFirst 20 bytes:")
        for i in range(min(20, len(data))):
            print(f"{data[i]:02X} ", end='')
            if (i+1) % 16 == 0:
                print()
        print()

        return data, trigger_idx
    else:
        print(f"❌ Error: Expected {frame_len} bytes, got {len(data)}")
        return None, None

if __name__ == '__main__':
    # 根据你的系统修改端口号
    # Windows: 'COM3', 'COM4' 等
    # Linux: '/dev/ttyUSB0'
    # macOS: '/dev/cu.usbserial-XXX'

    data, trig_idx = receive_logic_analyzer_data(port='COM3')

    if data:
        print("\n📊 Data Analysis:")
        print(f"  Total samples: {len(data)}")
        print(f"  Trigger at: byte {trig_idx}")
        print(f"  Pre-trigger: {trig_idx} bytes")
        print(f"  Post-trigger: {len(data) - trig_idx} bytes")
```

运行：
```bash
python uart_receiver.py
```

预期输出：
```
Opening COM3 at 115200 baud...
Waiting for frame header (0x55 0xAA)...
✅ Header found: 0x55 0xAA
Frame Length: 2048 (0x0800)
Trigger Index: 1
Receiving 2048 bytes...
✅ Received 2048 bytes successfully!
Data saved to capture.bin

First 20 bytes:
21 21 63 63 65 65 67 67 69 69 6B 6B 6D 6D 6F 6F
71 71 73 73

📊 Data Analysis:
  Total samples: 2048
  Trigger at: byte 1
  Pre-trigger: 1 bytes
  Post-trigger: 2047 bytes
```

---

## 🎯 推荐的调试流程

1. **阶段 1：仿真验证（ModelSim）**
   - 已完成 ✅
   - 确认逻辑正确，接收到 2054 字节

2. **阶段 2：ILA 内部调试**
   - 添加 ILA 监控 tx_data, tx_valid, busy
   - 验证状态机和数据流正确

3. **阶段 3：CH340 实际通信测试** ⭐
   - 连接 CH340 硬件
   - 使用 Python 脚本接收数据
   - 验证端到端通信

---

## ❓ 常见问题

### Q1: 电脑端收不到数据？

**检查清单**：
- [ ] CH340 驱动已安装（设备管理器中能看到 COM 口）
- [ ] 硬件连接正确（TX → RX, GND → GND）
- [ ] 波特率匹配（FPGA 和上位机都是 115200）
- [ ] FPGA 的 uart_tx 引脚分配正确（查看约束文件）
- [ ] 已触发采样（capture_done = 1）

### Q2: 接收到乱码？

**可能原因**：
- 波特率不匹配 → 检查 FPGA 和上位机波特率
- 电平不匹配 → 确认 CH340 支持 3.3V 或使用电平转换
- 线缆接触不良 → 重新连接

### Q3: 只收到部分数据？

**可能原因**：
- 上位机接收缓冲区太小 → 增大 timeout
- UART 模块状态机卡死 → 用 ILA 检查 busy 信号
- BRAM 读取有问题 → 检查 rd_addr 是否正常递增

---

## 📝 下一步：上位机软件开发

接收到数据后，你可以：
1. **解析数据**：按照触发索引重排波形
2. **可视化显示**：使用 matplotlib 绘制波形图
3. **导出格式**：保存为 VCD 或 CSV 格式

示例代码见：`python/logic_analyzer_viewer.py`（待创建）

---

## 🎓 总结

| 调试阶段 | 工具 | 目的 |
|----------|------|------|
| 逻辑验证 | ModelSim 仿真 | 验证设计正确性 ✅ 已完成 |
| 内部调试 | ILA | 查看内部信号 |
| 端到端测试 | CH340 + Python | 验证实际通信 ⭐ **推荐** |

**建议顺序**：先用 ILA 确认内部信号无误，再用 CH340 进行实际通信测试。
