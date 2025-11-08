`timescale 1ns / 1ps
/*
 * 模块名称: sample_rate_divider
 * 功能概述: 基于32MHz基准时钟产生采样使能脉冲 sample_en。通过3位档位选择
 *           rate_sel 选择分频比,表如下:
 *
 *   rate_sel | 分频比 | 采样率(基于32MHz)
 *   ---------|--------|-------------------
 *      0     |   1    | 32  MHz
 *      1     |   2    | 16  MHz
 *      2     |   4    | 8   MHz
 *      3     |   8    | 4   MHz
 *      4     |  16    | 2   MHz
 *      5     |  32    | 1   MHz
 *      6     |  64    | 500 kHz
 *      7     | 128    | 250 kHz
 *
 * 端口说明:
 * - clk      : 基准时钟(目标为32MHz;当前顶层临时用25MHz占位,需后续用PLL替换)。
 * - rst_n    : 低有效复位。
 * - rate_sel : 档位选择[2:0]。
 * - sample_en: 1个clk周期的采样使能脉冲(沿此脉冲进行一次采样)。
 *
 * 设计说明:
 * - 当 rate_sel 改变时,内部计数器同步清零以避免毛刺/不完整周期。
 */
module sample_rate_divider (
    input  wire       clk,
    input  wire       rst_n,
    input  wire [2:0] rate_sel,
    output reg        sample_en
);
    // 分频值:1 << rate_sel(1..128)
    wire [7:0] div_val = 8'd1 << rate_sel;

    reg [7:0] cnt;
    reg [2:0] rate_sel_d1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt        <= 8'd0;
            rate_sel_d1<= 3'd0;
            sample_en  <= 1'b0;
        end else begin
            // 采样脉冲默认拉低
            sample_en <= 1'b0;

            // 档位变化时,同步清零计数器,防止输出毛刺
            if (rate_sel != rate_sel_d1) begin
                rate_sel_d1 <= rate_sel;
                cnt         <= 8'd0;
            end else begin
                if (cnt == (div_val - 1'b1)) begin
                    cnt       <= 8'd0;
                    sample_en <= 1'b1; // 发出1个clk周期的采样使能
                end else begin
                    cnt <= cnt + 1'b1;
                end
            end
        end
    end
endmodule
