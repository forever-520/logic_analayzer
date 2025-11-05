`timescale 1ns / 1ps
/*
 * ============================================================================
 * 模块名称: uart_tx
 * 功能概述: 8N1 UART 发送器（底层字节发送模块）
 * ============================================================================
 *
 * 功能说明:
 *   这是一个标准的 UART 发送器，采用 8N1 格式（8 数据位、无校验位、1 停止位）
 *   - 空闲状态时 uart_tx 保持高电平
 *   - 收到 tx_valid 信号后，按以下顺序发送 10 个 bit：
 *     [起始位(0)] + [数据位 D0~D7(LSB先)] + [停止位(1)]
 *   - 波特率由系统时钟分频产生
 *
 * 参数说明:
 *   CLK_FREQ  : 系统时钟频率（Hz），例如 50_000_000 表示 50MHz
 *   BAUD_RATE : 目标串口波特率（bps），例如 115200
 *
 * 端口说明:
 *   clk       : 系统时钟输入
 *   rst_n     : 低有效复位信号（复位时为 0）
 *   tx_data   : [7:0] 待发送的字节数据（8位）
 *   tx_valid  : 发送请求信号（握手协议：当 tx_ready=1 时，拉高 tx_valid 启动发送）
 *   tx_ready  : 发送器空闲指示（1=空闲，可以接收新字节；0=忙碌中）
 *   uart_tx   : UART 串口发送引脚（连接到芯片 TX 管脚或 CH340 RX 管脚）
 *
 * 使用示例:
 *   当外部模块想发送 0x55 时：
 *   1. 等待 tx_ready == 1
 *   2. 拉高 tx_valid，同时给出 tx_data = 0x55
 *   3. 下一拍 tx_ready 变为 0，开始发送
 *   4. 发送完成后 tx_ready 恢复为 1
 *
 * ============================================================================
 */

module uart_tx #(
    parameter integer CLK_FREQ  = 50_000_000,  // 系统时钟频率 50MHz
    parameter integer BAUD_RATE = 115200       // 波特率 115200 bps
)(
    input  wire       clk,        // 系统时钟
    input  wire       rst_n,      // 低有效复位

    input  wire [7:0] tx_data,    // 待发送字节
    input  wire       tx_valid,   // 发送请求（握手信号）
    output wire       tx_ready,   // 空闲标志（1=可以发送新字节）

    output reg        uart_tx     // 串口 TX 输出引脚
);

    // ========================================================================
    // 波特率分频器参数计算
    // ========================================================================
    // BAUD_DIV: 每个 bit 需要的时钟周期数
    // 例如：50MHz / 115200 = 434.03 ≈ 434 个时钟周期/bit
    localparam integer BAUD_DIV = CLK_FREQ / BAUD_RATE;
    // BAUD_CNT_W: 计数器位宽（自动计算需要多少位）
    localparam integer BAUD_CNT_W = $clog2(BAUD_DIV);

    // 波特率计数器和时钟使能信号
    reg [BAUD_CNT_W-1:0] baud_cnt;  // 波特率计数器（0 到 BAUD_DIV-1）
    reg baud_tick;                   // 波特率 tick 脉冲（每个 bit 时间产生一次）

    // ========================================================================
    // 波特率分频器：产生每个 bit 的时序基准
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt  <= 0;
            baud_tick <= 1'b0;
        end else begin
            if (baud_cnt == BAUD_DIV-1) begin
                // 计数到达分频值，产生一个 tick 脉冲
                baud_cnt  <= 0;
                baud_tick <= 1'b1;      // tick 脉冲只持续 1 个时钟周期
            end else begin
                baud_cnt  <= baud_cnt + 1'b1;
                baud_tick <= 1'b0;
            end
        end
    end

    // ========================================================================
    // 状态机定义：UART 发送控制
    // ========================================================================
    // 状态编码
    localparam S_IDLE  = 2'd0;  // 空闲状态：等待发送请求
    localparam S_START = 2'd1;  // 发送起始位（0）
    localparam S_DATA  = 2'd2;  // 发送 8 个数据位（D0~D7，LSB 先发）
    localparam S_STOP  = 2'd3;  // 发送停止位（1）

    // 状态机寄存器
    reg [1:0] state;      // 当前状态
    reg [2:0] bit_idx;    // 数据位索引（0~7）
    reg [7:0] shifter;    // 移位寄存器（用于逐位发送）

    // tx_ready 信号：只有在 IDLE 状态时才能接收新数据
    assign tx_ready = (state == S_IDLE);

    // ========================================================================
    // 状态机主逻辑：控制 UART 发送时序
    // ========================================================================
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            bit_idx <= 3'd0;
            shifter <= 8'h00;
            uart_tx <= 1'b1;        // 复位时 TX 保持高电平（UART 空闲状态）
        end else begin
            case (state)
                // ============================================================
                // S_IDLE: 空闲状态
                // ============================================================
                // 功能：等待外部模块发送请求（tx_valid）
                // 跳转：收到 tx_valid 后，锁存数据并转到 S_START 状态
                S_IDLE: begin
                    uart_tx <= 1'b1;    // 保持高电平（空闲状态）
                    if (tx_valid) begin
                        shifter <= tx_data;  // 锁存待发送的字节
                        bit_idx <= 3'd0;     // 复位 bit 计数器
                        state   <= S_START;  // 转到发送起始位状态
                    end
                end

                // ============================================================
                // S_START: 发送起始位
                // ============================================================
                // 功能：拉低 uart_tx（起始位=0），持续一个 bit 时间
                // 跳转：baud_tick 到来时，转到 S_DATA 状态
                S_START: begin
                    uart_tx <= 1'b0;    // 起始位固定为 0
                    if (baud_tick) begin
                        state <= S_DATA;     // 一个 bit 时间后，开始发送数据位
                    end
                end

                // ============================================================
                // S_DATA: 发送 8 个数据位（D0~D7）
                // ============================================================
                // 功能：
                //   - 每次 baud_tick 到来时，发送 shifter[0]（LSB 先发）
                //   - 右移 shifter，准备下一个 bit
                //   - 发送完 8 个 bit 后，转到 S_STOP 状态
                // 注意：UART 协议规定低位先发（LSB first）
                S_DATA: begin
                    uart_tx <= shifter[0];   // 输出当前最低位
                    if (baud_tick) begin
                        // 右移移位寄存器（高位补 0）
                        shifter <= {1'b0, shifter[7:1]};

                        if (bit_idx == 3'd7) begin
                            // 已发送 8 个 bit（D0~D7），转到停止位
                            state <= S_STOP;
                        end else begin
                            // 继续发送下一个 bit
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end
                end

                // ============================================================
                // S_STOP: 发送停止位
                // ============================================================
                // 功能：拉高 uart_tx（停止位=1），持续一个 bit 时间
                // 跳转：baud_tick 到来时，回到 S_IDLE 状态
                S_STOP: begin
                    uart_tx <= 1'b1;    // 停止位固定为 1
                    if (baud_tick) begin
                        state <= S_IDLE;     // 发送完成，回到空闲状态
                    end
                end

                // 默认状态：防止状态机进入未定义状态
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
