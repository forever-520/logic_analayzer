`timescale 1ns / 1ps
/*
 * 测试平台: tb_test_signal_gen
 * 功能概述: 逐一验证 4 种测试模式（00递增、01方波、10LFSR、11AA/55），并打印部分输出。
 */
module tb_test_signal_gen;

    reg         clk;
    reg         rst_n;
    reg         enable;
    reg  [1:0]  pattern_sel;
    wire [7:0]  test_data;

    // 实例化被测模块
    test_signal_gen #(
        .DATA_WIDTH(8)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .pattern_sel(pattern_sel),
        .test_data(test_data)
    );

    // 时钟生成 (100MHz)
    initial clk = 0;
    always #5 clk = ~clk;

    integer i;

    // 测试激励
    initial begin
        rst_n = 0;
        enable = 0;
        pattern_sel = 0;

        #20;
        rst_n = 1;
        #10;

        // 测试模式0: 递增计数
        $display("========== 测试模式0: 递增计数 ==========");
        pattern_sel = 2'b00;
        enable = 1;
        #1000;

        // 测试模式1: 方波
        $display("========== 测试模式1: 方波 ==========");
        pattern_sel = 2'b01;
        #2000;

        // 测试模式2: 伪随机
        $display("========== 测试模式2: 伪随机LFSR ==========");
        pattern_sel = 2'b10;
        #1000;

        // 测试模式3: 0xAA/0x55交替
        $display("========== 测试模式3: AA/55交替 ==========");
        pattern_sel = 2'b11;
        #1000;

        // 测试使能关闭
        $display("========== 测试使能关闭 ==========");
        enable = 0;
        #500;

        $display("测试信号生成器仿真完成");
        $finish;
    end

    // 监控前几个输出
    initial begin
        for (i = 0; i < 100; i = i + 1) begin
            @(posedge clk);
            if (enable && i < 20) begin
                $display("时间=%0t, pattern=%d, test_data=%h", $time, pattern_sel, test_data);
            end
        end
    end

endmodule
