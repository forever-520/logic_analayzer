`timescale 1ns / 1ps
/*
 * 模块名称: uart_bram_streamer
 * 功能概述: 通过 UART 以“帧”的形式发送 BRAM 中的完整缓冲数据，用于导出采样结果。
 *           帧格式: 0x55 0xAA | LEN_L LEN_H | TRIG_L TRIG_H | DATA[0..LEN-1]
 *           其中 LEN = 2^ADDR_WIDTH，TRIG_* 为触发参考地址（供上位机重排显示）。
 *
 * 参数说明:
 * - DATA_WIDTH: BRAM 数据位宽（字节发送）。
 * - ADDR_WIDTH: BRAM 地址宽度（总字节数=2^ADDR_WIDTH）。
 * - CLK_FREQ  : 输入时钟频率（Hz）。
 * - BAUD_RATE : 串口波特率。
 *
 * 端口说明:
 * - clk, rst_n       : 时钟与低有效复位。
 * - start            : 上升沿开始发送一帧。
 * - busy, done       : 发送中/单帧完成指示。
 * - trigger_index[A-1:0]: 触发参考地址（随帧发送）。
 * - rd_addr, rd_data : BRAM 读口（同步读，读数据延迟一拍有效）。
 * - uart_tx          : 串口发送引脚。
 */

// 将 BRAM 中的数据以帧的形式通过 UART 发送到主机。
// 帧格式：0x55 0xAA | LEN_L LEN_H | TRIG_L TRIG_H | DATA[0..LEN-1]
// 说明：LEN = 2^ADDR_WIDTH（整个缓冲区长度）。

module uart_bram_streamer #(
    parameter integer DATA_WIDTH = 8,
    parameter integer ADDR_WIDTH = 11,
    parameter integer CLK_FREQ   = 50_000_000,
    parameter integer BAUD_RATE  = 115200
)(
    input  wire                   clk,
    input  wire                   rst_n,

    input  wire                   start,          // 置1开始发送一帧
    output reg                    busy,           // 正在发送
    output reg                    done,           // 单帧发送完成脉冲

    input  wire [ADDR_WIDTH-1:0]  trigger_index,  // 触发参考地址（将随帧发送）

    // BRAM 读口（与 sample_buffer 的读端口对接）
    output reg  [ADDR_WIDTH-1:0]  rd_addr,
    input  wire [DATA_WIDTH-1:0]  rd_data,

    output wire                   uart_tx
);

    localparam integer DEPTH = (1<<ADDR_WIDTH);
    localparam [15:0]  LEN16 = (16'd1 << ADDR_WIDTH);
    localparam [ADDR_WIDTH-1:0] DEPTH_M1 = (1<<ADDR_WIDTH) - 1;

    // UART TX 子模块
    wire       tx_ready;
    reg  [7:0] tx_data;
    reg        tx_valid;

    uart_tx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) u_tx (
        .clk(clk),
        .rst_n(rst_n),
        .tx_data(tx_data),
        .tx_valid(tx_valid),
        .tx_ready(tx_ready),
        .uart_tx(uart_tx)
    );

    // 状态机
    localparam S_IDLE   = 3'd0;
    localparam S_HDR    = 3'd1;
    localparam S_PREF   = 3'd2; // 预取首字节（考虑同步读延迟）
    localparam S_DATA   = 3'd3;
    localparam S_DONE   = 3'd4;

    reg [2:0]  state;
    reg [2:0]  hdr_idx;       // 0..5
    reg [ADDR_WIDTH-1:0] addr;
    reg [ADDR_WIDTH-1:0] bytes_sent;
    reg [7:0]  data_latched;  // 对齐 BRAM 一拍延迟
    reg        have_data;

    // 组合：根据 hdr_idx 选择要发的头字节
    wire [15:0] trig16 = { {(16-ADDR_WIDTH){1'b0}}, trigger_index };
    wire [7:0] hdr_byte = (hdr_idx==3'd0) ? 8'h55 :
                          (hdr_idx==3'd1) ? 8'hAA :
                          (hdr_idx==3'd2) ? LEN16[7:0] :
                          (hdr_idx==3'd3) ? LEN16[15:8] :
                          (hdr_idx==3'd4) ? trig16[7:0] :
                                            trig16[15:8];

    // 主过程
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state      <= S_IDLE;
            busy       <= 1'b0;
            done       <= 1'b0;
            hdr_idx    <= 3'd0;
            addr       <= {ADDR_WIDTH{1'b0}};
            bytes_sent <= {ADDR_WIDTH{1'b0}};
            rd_addr    <= {ADDR_WIDTH{1'b0}};
            data_latched <= 8'h00;
            have_data  <= 1'b0;
            tx_data    <= 8'h00;
            tx_valid   <= 1'b0;
        end else begin
            done     <= 1'b0;
            tx_valid <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy    <= 1'b0;
                    hdr_idx <= 3'd0;
                    if (start) begin
                        busy    <= 1'b1;
                        state   <= S_HDR;
                    end
                end

                S_HDR: begin
                    if (tx_ready) begin
                        tx_data  <= hdr_byte;
                        tx_valid <= 1'b1;
                        if (hdr_idx == 3'd5) begin
                            // 头部发完，开始预取数据
                            addr       <= {ADDR_WIDTH{1'b0}};
                            rd_addr    <= {ADDR_WIDTH{1'b0}};
                            bytes_sent <= {ADDR_WIDTH{1'b0}};
                            have_data  <= 1'b0;
                            state      <= S_PREF;
                        end else begin
                            hdr_idx <= hdr_idx + 1'b1;
                        end
                    end
                end

                S_PREF: begin
                    // 同步 RAM 读延迟一拍：本拍给地址，下一拍拿到数据
                    rd_addr   <= addr;
                    have_data <= 1'b0;
                    state     <= S_DATA;
                end

                S_DATA: begin
                    // 每拍先锁存当前读数据
                    data_latched <= rd_data;
                    // 第一次进入该状态时 have_data=0，锁存后置1，下一拍可发送
                    have_data    <= 1'b1;

                    // 当 UART 准备好且我们有有效数据时发送
                    if (tx_ready && have_data) begin
                        tx_data  <= data_latched;
                        tx_valid <= 1'b1;

                        // 准备下一字节
                        addr         <= addr + 1'b1;
                        rd_addr      <= addr + 1'b1;
                        bytes_sent   <= bytes_sent + 1'b1;

                        if (bytes_sent == DEPTH_M1) begin
                            // 最后一个字节已发送，转结束
                            state <= S_DONE;
                        end
                    end
                end

                S_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    if (!start) begin
                        state <= S_IDLE;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
