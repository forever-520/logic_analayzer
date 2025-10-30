`timescale 1ns / 1ps
/*
 * 测试平台: tb_input_synchronizer
 * 功能概述: 验证多比特异步输入同步器在 2 级同步下的延迟与稳定性。
 * 刺激模式: 先给出若干稳定值，再注入快速变化以模拟亚稳态风险。
 * 观察点  : data_out 应在两个 clk 周期后稳定地跟随 data_in 变化。
 */
module tb_input_synchronizer;

    reg         clk;
    reg         rst_n;
    reg  [7:0]  data_in;
    wire [7:0]  data_out;

    // 实例化被测模块
    input_synchronizer #(
        .DATA_WIDTH(8)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .data_in(data_in),
        .data_out(data_out)
    );

    // 时钟生成 (100MHz)
    initial clk = 0;
    always #5 clk = ~clk;

    // 测试激励
    initial begin
        rst_n = 0;
        data_in = 8'h00;

        // 复位
        #20;
        rst_n = 1;

        // 测试数据变化
        #10 data_in = 8'hAA;
        #30 data_in = 8'h55;
        #30 data_in = 8'hF0;
        #30 data_in = 8'h0F;

        // 测试亚稳态情况 (快速变化)
        #10 data_in = 8'h11;
        #2  data_in = 8'h22;
        #2  data_in = 8'h33;
        #2  data_in = 8'h44;

        #50;
        $display("仿真完成");
        $finish;
    end

    // 监控输出
    initial begin
        $monitor("时间=%0t ns, rst_n=%b, data_in=%h, data_out=%h",
                 $time, rst_n, data_in, data_out);
    end

endmodule
