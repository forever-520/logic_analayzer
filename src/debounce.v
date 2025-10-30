`timescale 1ns / 1ps
/*
 * 模块名称: debounce
 * 功能概述: 对低有效按键/输入进行同步与消抖。输入稳定为低持续 CNT_MAX 周期后，
 *           在释放前仅输出一个时钟周期的脉冲标志位，用于“单击”触发。
 *
 * 参数说明:
 * - CNT_MAX: 低电平持续计数阈值（默认约 20ms@50MHz）。
 *
 * 端口说明:
 * - clk     : 时钟。
 * - rst_n   : 低电平异步复位。
 * - btn_in  : 低有效原始按键信号/输入信号。
 * - btn_flag: 消抖后的单拍脉冲（一个 clk 周期）。
 */
module debounce #(
    parameter CNT_MAX = 20'd999_999   // ~20ms @ 50MHz
)(
    input  wire clk,
    input  wire rst_n,
    input  wire btn_in,      // active low
    output reg  btn_flag     // one-clock pulse
);

    reg [19:0] cnt;
    reg btn_in_d1, btn_in_d2;

    // 双寄存器同步
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            btn_in_d1 <= 1'b1;
            btn_in_d2 <= 1'b1;
        end else begin
            btn_in_d1 <= btn_in;
            btn_in_d2 <= btn_in_d1;
        end
    end

    // 消抖计数器
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            cnt <= 20'd0;
        else if (btn_in_d2 == 1'b1)  // 按键释放，复位计数器
            cnt <= 20'd0;
        else if (cnt < CNT_MAX)      // 按键按下，计数
            cnt <= cnt + 1'b1;
    end

    // 单脉冲输出
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            btn_flag <= 1'b0;
        else
            btn_flag <= (cnt == CNT_MAX - 1'b1);
    end

endmodule
