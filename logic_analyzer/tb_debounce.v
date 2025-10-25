`timescale 1ns / 1ps

module tb_debounce;

    reg  clk;
    reg  rst_n;
    reg  btn_in;
    wire btn_flag;

    localparam integer SIM_CNT_MAX = 10'd19;   // 缩短仿真下的消抖时间（约20个时钟）

    debounce #(
        .CNT_MAX(SIM_CNT_MAX)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .btn_in(btn_in),
        .btn_flag(btn_flag)
    );

    // 时钟生成 (1MHz for simulation, 1us period)
    initial clk = 0;
    always #500 clk = ~clk;  // 1kHz = 1ms period

    // 测试激励
    initial begin
        rst_n = 0;
        btn_in = 1;  // 初始状态：未按下（高电平）

        #2000;  // 2ms
        rst_n = 1;

        // 测试按下抖动（高→低，模拟按键按下）
        #5000 btn_in = 0;
        #100  btn_in = 1;
        #100  btn_in = 0;
        #100  btn_in = 1;
        #100  btn_in = 0;  // 稳定低电平（按下）

        #20000;  // 等待消抖完成

        // 测试释放抖动（低→高，模拟按键释放）
        #5000 btn_in = 1;
        #100  btn_in = 0;
        #100  btn_in = 1;
        #100  btn_in = 0;
        #100  btn_in = 1;  // 稳定高电平（释放）

        #20000;
        $display("消抖仿真完成");
        $finish;
    end

    // 监控按键脉冲
    always @(posedge clk) begin
        if (btn_flag) begin
            $display("时间=%0t us, 检测到按键脉冲！", $time/1000);
        end
    end

endmodule
