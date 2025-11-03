`timescale 1ns / 1ps
/*
 * 测试平台: tb_sample_buffer
 * 功能概述: 验证同步双口 BRAM 读写。先按地址写入 0..255，再按地址读出比对。
 * 能否展示采集到的数据: 可以。该仿真会从 RAM 读出并在不一致时打印，
 *                       你也可以将循环中加入 $display 打印前 N 个 rd_data 即可直观看到“存储的数据”。
 */
module tb_sample_buffer;

    reg         wr_clk;
    reg         wr_en;
    reg  [10:0] wr_addr;
    reg  [7:0]  wr_data;

    reg         rd_clk;
    reg  [10:0] rd_addr;
    wire [7:0]  rd_data;

    // 实例化被测模块
    sample_buffer #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(11)
    ) uut (
        .wr_clk(wr_clk),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .rd_clk(rd_clk),
        .rd_addr(rd_addr),
        .rd_data(rd_data)
    );

    // 写时钟生成 (100MHz)
    initial wr_clk = 0;
    always #5 wr_clk = ~wr_clk;

    // 读时钟生成 (50MHz)
    initial rd_clk = 0;
    always #10 rd_clk = ~rd_clk;

    integer i;

    // 测试激励
    initial begin
        wr_en = 0;
        wr_addr = 0;
        wr_data = 0;
        rd_addr = 0;

        #20;

        // 写入测试数据
        wr_en = 1;
        for (i = 0; i < 256; i = i + 1) begin
            @(posedge wr_clk);
            wr_addr = i;
            wr_data = i[7:0];  // 写入地址对应的数据
        end

        wr_en = 0;
        #50;

        // 读取测试数据
        for (i = 0; i < 256; i = i + 1) begin
            @(posedge rd_clk);
            rd_addr = i;
            #1;
            @(posedge rd_clk);
            if (rd_data !== i[7:0]) begin
                $display("错误: 地址 %d, 期望 %h, 实际 %h", i, i[7:0], rd_data);
            end
        end

        #100;
        $display("BRAM测试完成");
        $finish;
    end

endmodule
