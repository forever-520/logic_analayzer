`timescale 1ns / 1ps
/*
 * 测试平台: tb_logic_analyzer_core
 * 功能概述: 针对逻辑分析仪核心验证电平/边沿触发、OR/AND-ACC/AND-COIN 三种模式，
 *           观察 wr_en/wr_addr/wr_data 写口以及 captured/triggered/done 标志。
 * 能否展示“存储后的数据”: 本测试仅观察写口，不包含 BRAM 读出。
 *                       若要查看已存储内容，可配合 sample_buffer 或使用 uart_bram_streamer。
 */
module tb_logic_analyzer_core;

    reg         clk;
    reg         rst_n;
    reg  [7:0]  sample_data;
    reg         trigger_enable;
    reg  [7:0]  trigger_value;
    reg  [7:0]  trigger_mask;
    reg  [7:0]  edge_trigger;   // 每位控制：1=边沿 0=电平
    reg  [7:0]  trigger_type;   // 每位：边沿(0上升/1下降) 电平(0高/1低)
    reg  [1:0]  trigger_mode;      // 00=OR,01=AND-ACC,10=AND-COIN

    wire        capturing;
    wire        triggered;
    wire        capture_done;
    wire        wr_en;
    wire [10:0] wr_addr;
    wire [7:0]  wr_data;
    wire [10:0] trigger_index;

    // 实例化被测模块
    logic_analyzer_core #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(11)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .sample_data(sample_data),
        .trigger_enable(trigger_enable),
        .trigger_value(trigger_value),
        .trigger_mask(trigger_mask),
        .edge_trigger(edge_trigger),
        .trigger_type(trigger_type),
        .trigger_mode(trigger_mode),
        .trigger_mode_is_or(trigger_mode[0]),
        .capturing(capturing),
        .triggered(triggered),
        .capture_done(capture_done),
        .trigger_index(trigger_index),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data)
    );

    // 时钟生成 (100MHz)
    initial clk = 0;
    always #5 clk = ~clk;

    integer i;

    // 测试激励
    initial begin
        rst_n = 0;
        sample_data = 8'h00;
        trigger_enable = 0;
        trigger_value = 8'hAA;
        trigger_mask = 8'hFF;
        edge_trigger = 8'h00;
        trigger_type = 8'hFF;
        trigger_mode = 2'd0; // OR

        #20;
        rst_n = 1;
        #20;

        $display("========== 测试1: 电平触发 ==========");
        trigger_enable = 1;

        // 产生递增数据
        for (i = 0; i < 200; i = i + 1) begin
            @(posedge clk);
            sample_data = i[7:0];
            if (i == 170) sample_data = 8'hAA;  // 触发点
        end

        wait(triggered);
        $display("触发检测到！地址: %d", wr_addr);

        wait(capture_done);
        $display("采样完成");

        trigger_enable = 0;
        #100;

        $display("========== 测试2: 上升沿触发 ==========");
        rst_n = 0;
        #20;
        rst_n = 1;
        #20;

        edge_trigger = 8'hFF; // 边沿
        trigger_type = 8'hFF; // 下降沿（对位7）
        trigger_value = 8'h80;
        trigger_enable = 1;
        trigger_mode   = 2'd0; // OR

        for (i = 0; i < 300; i = i + 1) begin
            @(posedge clk);
            if (i < 100)      sample_data = 8'h00;
            else if (i == 100) sample_data = 8'h80;  // 上升沿
            else              sample_data = 8'h80;
        end

        wait(triggered);
        $display("上升沿触发检测到！");

        wait(capture_done);
        $display("测试完成");

        trigger_enable = 0;
        #100;

        // ========= 测试3: 电平触发（OR/AND） =========
        $display("========== 测试3: 电平触发（OR/AND） ==========");
        rst_n = 0; #20; rst_n = 1; #20;

        // 3a) OR 模式：CH0 高电平触发
        trigger_mode = 2'd0;     // OR
        trigger_enable     = 1'b1;
        trigger_mask       = 8'b0000_0011; // 使能 CH1..CH0
        edge_trigger       = 8'b0000_0000; // 全部电平触发
        trigger_type       = 8'b0000_0010; // CH1:低电平(1); CH0:高电平(0)
        sample_data        = 8'h00;       // CH1=0, CH0=0

        // 使 CH0 拉高 -> 立即触发（OR）
        repeat(5) @(posedge clk);
        sample_data[0] = 1'b1; // CH0=1 高电平

        wait(triggered);
        $display("电平-OR触发: trigger_index=%0d addr=%0d", trigger_index, wr_addr);

        trigger_enable = 0; #50;

        // 3b) AND-ACC 模式：CH0 高电平 与 CH1 低电平 同时满足（电平实时、两者同时满足才触发）
        rst_n = 0; #20; rst_n = 1; #20;
        trigger_mode = 2'd1;     // AND-ACC
        trigger_enable     = 1'b1;
        trigger_mask       = 8'b0000_0011;
        edge_trigger       = 8'b0000_0000; // 电平
        trigger_type       = 8'b0000_0010; // CH1:低, CH0:高
        sample_data        = 8'b0000_0010; // CH1=1, CH0=0 (都不满足)

        // 先让 CH0=1，但 CH1 仍=1（不满足低） -> 不触发
        repeat(5) @(posedge clk);
        sample_data        = 8'b0000_0011; // CH1=1, CH0=1
        repeat(10) @(posedge clk);
        // 再让 CH1=0，与 CH0=1 同时满足 -> 触发
        sample_data        = 8'b0000_0001; // CH1=0, CH0=1

        wait(triggered);
        $display("电平-AND触发: trigger_index=%0d addr=%0d", trigger_index, wr_addr);

        wait(capture_done);
        $display("所有测试完成");
        $finish;
    end

    // 监控
    initial begin
        $monitor("时间=%0t, 状态: capturing=%b triggered=%b done=%b, wr_en=%b addr=%d data=%h",
                 $time, capturing, triggered, capture_done, wr_en, wr_addr, wr_data);
    end

endmodule
