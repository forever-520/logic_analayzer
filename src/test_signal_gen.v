`timescale 1ns / 1ps
/*
 * 模块名称: test_signal_gen
 * 功能概述: 片上测试信号发生器。提供 4 种可选模式用于本地验证：
 *           00=递增计数；01=方波；10=LFSR 伪随机；11=0xAA/0x55 交替。
 *
 * 参数说明:
 * - DATA_WIDTH: 输出位宽。
 *
 * 端口说明:
 * - clk, rst_n : 时钟与低有效复位。
 * - enable     : 1 时输出有效并运行；0 时清零停止。
 * - pattern_sel: 工作模式选择（见上）。
 * - test_data  : 输出测试数据。
 */
module test_signal_gen #(
    parameter DATA_WIDTH = 8
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     enable,
    input  wire [1:0]               pattern_sel,  // 模式选择
    output reg  [DATA_WIDTH-1:0]    test_data
);

    reg [15:0] counter;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            counter   <= 0;
            test_data <= 0;
        end else if (enable) begin
            counter <= counter + 1'b1;

            case (pattern_sel)
                2'b00: begin  // 递增计数
                    test_data <= counter[7:0];
                end

                2'b01: begin  // 方波 (50% duty cycle)
                    test_data <= counter[8] ? 8'hFF : 8'h00;
                end

                2'b10: begin  // 伪随机 (LFSR)
                    test_data <= {test_data[6:0], test_data[7] ^ test_data[5] ^ test_data[4] ^ test_data[3]};
                    if (test_data == 0) test_data <= 8'hA5;  // 防止全0
                end

                2'b11: begin  // 固定模式 (0xAA, 0x55交替)
                    test_data <= counter[4] ? 8'hAA : 8'h55;
                end
            endcase
        end else begin
            counter   <= 0;
            test_data <= 0;
        end
    end

endmodule
