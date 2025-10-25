`timescale 1ns / 1ps

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
