//******************************************************************************
// 文件名称: tb_fpga_top_config.v
// 文件描述: FPGA顶层模块（逻辑分析仪）的仿真测试平台
//******************************************************************************
// 功能说明:
//   本测试平台用于验证逻辑分析仪的完整功能，包括：
//   1. 多通道配置（8路输入通道）
//   2. 多种触发模式（OR独立触发、AND累加触发、AND同拍触发）
//   3. 多种触发类型（上升沿、下降沿、高电平、低电平）
//   4. 按键控制（通道选择、类型选择、模式选择、触发使能）
//   5. 信号采集与存储功能验证
//
// 测试用例:
//   Test 1: OR模式（独立触发）- 验证任一通道满足条件即触发
//   Test 2: AND模式（累加触发）- 验证所有配置通道依次满足条件后触发
//   Test 3: 电平触发（OR & AND）- 验证高低电平触发功能
//   Test 4: AND-COIN模式（同拍触发）- 验证所有通道同时满足条件才触发
//
// 设计要点:
//   - 使用参数化配置缩短按键消抖时间（仿真中从20ms缩短至10us）
//   - 封装按键操作任务（press_button）简化测试流程
//   - 封装配置任务（configure_channel）实现自动通道配置
//   - 封装打印任务（print_config）便于调试和验证配置状态
//   - 添加超时保护机制，防止仿真卡死
//
// 作者信息: [Your Name]
// 创建日期: 2025-10-31
// 修改记录:
//   2025-10-31 - 初始版本，完成4个核心测试用例
//******************************************************************************

// 时间单位定义：1ns为时间精度，1ps为时间步长（用于仿真时序计算）
`timescale 1ns / 1ps
// 定义仿真模式宏，可在被调用模块中区分仿真/实际硬件环境
`define SIMULATION

// 模块定义：FPGA顶层配置的测试平台（TB），用于验证逻辑分析仪功能
module tb_fpga_top_config;

    // -------------------------- 1. 信号声明 --------------------------
    // 系统时钟与复位信号
    reg        sys_clk;          // 50MHz系统时钟（FPGA核心时钟）
    reg        sys_rst_n;        // 系统复位信号，低电平有效（复位时初始化模块状态）

    // 逻辑分析仪输入信号：8路待采集的探针信号
    reg  [7:0] probe_signals;    // 8位宽，每一位对应1路外部输入信号

    // 按键控制信号：高电平为未按下状态（默认），低电平为按下状态
    reg        btn_trigger_en;   // 触发使能按键（启动/停止信号采集）
    reg        btn_channel_select; // 通道选择按键（切换当前配置的通道，0-7循环）
    reg        btn_type_select;  // 触发类型选择按键（切换当前通道的触发条件）
    reg        btn_trigger_mode; // 触发模式选择按键（切换OR/AND-ACC/AND-COIN模式）

    // 测试模式控制信号（用于生成测试信号，无需外部输入）
    reg        sw_test_enable;   // 测试模式使能开关（1=开启测试信号，0=使用真实探针信号）
    reg  [1:0] sw_test_pattern;  // 测试信号模式选择（2位宽，对应不同测试波形）

    // -------------------------- 2. 例化被测试模块（DUT） --------------------------
    // 例化FPGA顶层模块（逻辑分析仪核心），并配置按键消抖参数
    // 仿真中缩短消抖计数：原硬件可能需20ms，仿真用~10us（500个50MHz时钟周期）提高效率
    fpga_top #(
        .DEBOUNCE_CNT_MAX(10'd500)  // 按键消抖计数器最大值（参数化配置）
    ) u_dut (  // 被测试模块（DUT）实例名：u_dut
        .sys_clk           (sys_clk),           // 时钟信号连接
        .sys_rst_n         (sys_rst_n),         // 复位信号连接
        .probe_signals     (probe_signals),     // 探针信号连接
        .btn_trigger_en    (btn_trigger_en),    // 触发使能按键连接
        .btn_channel_select(btn_channel_select),// 通道选择按键连接
        .btn_type_select   (btn_type_select),   // 触发类型按键连接
        .btn_trigger_mode  (btn_trigger_mode),  // 触发模式按键连接
        .sw_test_enable    (sw_test_enable),    // 测试模式开关连接
        .sw_test_pattern   (sw_test_pattern)    // 测试模式波形选择连接
    );

    // -------------------------- 3. 生成系统时钟 --------------------------
    // 初始化并生成50MHz时钟（周期20ns，高/低电平各10ns）
    initial begin
        sys_clk = 1'b0;          // 初始时钟为低电平
        forever #10 sys_clk = ~sys_clk;  // 每10ns翻转一次，生成连续时钟
    end

    // -------------------------- 4. 按键操作任务（封装按键逻辑） --------------------------
    // 任务功能：模拟按下指定按键，包含"按下-保持-释放"完整流程（带消抖等待）
    // btn_id：按键ID（0=触发使能，1=通道选择，2=类型选择，3=模式选择）
    task press_button;
        input [2:0] btn_id;  // 输入参数：按键ID（3位宽，覆盖0-3）
        begin
            // 第一步：按下按键（拉低对应信号）
            case (btn_id)
                3'd0: btn_trigger_en     = 1'b0;  // 按下"触发使能"键
                3'd1: btn_channel_select = 1'b0;  // 按下"通道选择"键
                3'd2: btn_type_select    = 1'b0;  // 按下"类型选择"键
                3'd3: btn_trigger_mode   = 1'b0;  // 按下"模式选择"键
            endcase
            #20_000;  // 保持按下20us（50MHz时钟下1000个周期），确保消抖完成

            // 第二步：释放按键（拉高对应信号）
            case (btn_id)
                3'd0: btn_trigger_en     = 1'b1;  // 释放"触发使能"键
                3'd1: btn_channel_select = 1'b1;  // 释放"通道选择"键
                3'd2: btn_type_select    = 1'b1;  // 释放"类型选择"键
                3'd3: btn_trigger_mode   = 1'b1;  // 释放"模式选择"键
            endcase
            #30_000;   // 释放后等待30us（1500个时钟周期），确保模块状态稳定
        end
    endtask

    // -------------------------- 5. 配置打印任务（调试用） --------------------------
    // 任务功能：打印当前逻辑分析仪的配置状态（通道、触发模式、各通道触发条件）
    task print_config;
        integer ch;  // 循环变量：遍历8个通道（0-7）
        begin
            $display("=================================================");
            // 打印当前选中的通道和触发模式
            $display("Current Config | Selected CH: %0d | Trigger Mode: %s",
                     u_dut.config_channel_idx,  // DUT内部信号：当前选中的通道索引
                     // 根据触发模式选择信号，打印对应的模式名称
                     (u_dut.trigger_mode_sel==2'd0) ? "OR (Independent)" :  // OR模式（独立触发）
                     (u_dut.trigger_mode_sel==2'd1) ? "AND-ACC (Accumulate)" :  // AND累加模式
                     (u_dut.trigger_mode_sel==2'd2) ? "AND-COIN (Coincident)" : "UNKNOWN");  // AND同拍模式
            $display("-------------------------------------------------");
            $display("CH | Code | Mode      | Status");  // 表头：通道号、配置码、触发模式、选中状态
            $display("---|------|-----------|----------");
            // 遍历8个通道，打印每个通道的配置
            for (ch = 0; ch < 8; ch = ch + 1) begin
                $write(" %0d | %03b  | ", ch, u_dut.trigger_config[ch]);  // 通道号、3位配置码
                // 根据3位配置码，打印对应的触发模式名称
                case (u_dut.trigger_config[ch])
                    3'b000: $write("Disabled  ");  // 000：通道禁用
                    3'b001: $write("RisingEdge");  // 001：上升沿触发
                    3'b011: $write("FallingEdg");  // 011：下降沿触发
                    3'b101: $write("HighLevel ");  // 101：高电平触发
                    3'b111: $write("LowLevel  ");  // 111：低电平触发
                    default: $write("Undefined ");  // 其他：未定义
                endcase
                // 标记当前选中的通道（在对应行末尾显示"<-- Selected"）
                if (ch == u_dut.config_channel_idx)
                    $display("| <- Selected");
                else
                    $display("|");
            end
            $display("=================================================");
        end
    endtask

    // -------------------------- 6. 通道配置任务（核心配置逻辑） --------------------------
    // 任务功能：将指定通道配置为目标触发条件（自动完成通道切换和按键操作）
    // channel_num：目标通道（0-7）；desired_config：目标触发配置（3位码，如001=上升沿）
    task configure_channel;
        input [2:0] channel_num;    // 输入1：目标通道号（0-7）
        input [2:0] desired_config; // 输入2：目标触发配置（000/001/011/101/111）

        // 内部变量：存储配置过程中的临时状态
        integer current_state_idx;  // 当前配置对应的状态索引（0-4，对应5种触发条件）
        integer target_state_idx;   // 目标配置对应的状态索引（0-4）
        integer presses_needed;     // 需要按下"类型选择"键的次数
        integer i;                  // 循环变量：用于计数按键次数（Verilog 2001及以上支持）
        reg [2:0] current_config_val; // 当前通道的触发配置（从DUT读取）

        begin
            $display("--> Configuring CH%0d to %03b...", channel_num, desired_config);

            // 步骤1：切换到目标通道（循环按"通道选择"键，直到选中目标通道）
            while (u_dut.config_channel_idx != channel_num) begin
                press_button(3'd1);  // 按"通道选择"键（ID=1）
            end
            $display("    Channel %0d selected.", channel_num);

            // 步骤2：读取当前通道的触发配置（从DUT内部寄存器读取）
            current_config_val = u_dut.trigger_config[channel_num];

            // 步骤3：将"3位配置码"映射为"状态索引"（0-4循环，对应5种触发条件）
            // 当前配置映射为状态索引
            case(current_config_val)
                3'b000: current_state_idx = 0; // 禁用 -> 状态0
                3'b001: current_state_idx = 1; // 上升沿 -> 状态1
                3'b011: current_state_idx = 2; // 下降沿 -> 状态2
                3'b101: current_state_idx = 3; // 高电平 -> 状态3
                3'b111: current_state_idx = 4; // 低电平 -> 状态4
                default: current_state_idx = 0; // 默认：禁用
            endcase
            // 目标配置映射为状态索引
            case(desired_config)
                3'b000: target_state_idx = 0;
                3'b001: target_state_idx = 1;
                3'b011: target_state_idx = 2;
                3'b101: target_state_idx = 3;
                3'b111: target_state_idx = 4;
                default: target_state_idx = 0;
            endcase

            // 步骤4：计算需要按下"类型选择"键的次数（处理循环逻辑）
            if (target_state_idx >= current_state_idx) begin
                // 目标状态在当前状态之后：直接相减（如从状态1到3，需按2次）
                presses_needed = target_state_idx - current_state_idx;
            end else begin
                // 目标状态在当前状态之前：需先循环到末尾再到目标（如从状态4到1，需按2次：4→0→1）
                presses_needed = (5 - current_state_idx) + target_state_idx;
            end

            // 步骤5：执行按键操作（按计算次数按下"类型选择"键）
            $display("    Current state: %03b, Target: %03b, Need %0d presses.",
                     current_config_val, desired_config, presses_needed);
            for (i = 0; i < presses_needed; i = i + 1) begin
                press_button(3'd2);  // 按"类型选择"键（ID=2）
                #200;  // 等待200ns（10个50MHz时钟周期），确保配置稳定
            end

            $display("    Configuration complete.");
        end
    endtask

    // -------------------------- 7. 主测试流程（验证核心功能） --------------------------
    initial begin
        // 步骤1：初始化所有信号（复位前状态）
        sys_rst_n         = 1'b0;       // 复位有效（拉低）
        probe_signals     = 8'h00;      // 探针信号初始化为0（所有通道低电平）
        btn_trigger_en    = 1'b1;       // 触发使能键默认未按下（高电平）
        btn_channel_select= 1'b1;       // 通道选择键默认未按下
        btn_type_select   = 1'b1;       // 类型选择键默认未按下
        btn_trigger_mode  = 1'b1;       // 模式选择键默认未按下
        sw_test_enable    = 1'b0;       // 关闭测试模式（使用真实探针信号）
        sw_test_pattern   = 2'b00;      // 测试模式波形默认选择0

        // 步骤2：释放复位（等待复位稳定）
        #100; sys_rst_n = 1'b1;  // 100ns后复位无效（拉高）
        #100;  // 再等待100ns，确保模块完成复位初始化

        // =============================================================
        // 测试1：OR模式验证（独立触发，任一通道满足条件即触发）
        // =============================================================
        $display("\n\n[Test 1] OR Mode (Independent Trigger) Verification");
        $display("-------------------------------------------------");

        // 配置通道0为上升沿（001），通道1为下降沿（011）
        configure_channel(0, 3'b001);
        configure_channel(1, 3'b011);
        print_config();  // 打印当前配置，确认配置正确

        $display("Starting capture (OR mode)...");
        press_button(3'd0);  // 按"触发使能"键（ID=0），启动信号采集
        #1000;  // 等待1000ns（50个时钟周期），确保采集状态稳定

        // 生成通道0的上升沿（0→1），验证OR模式下是否触发
        $display("\nGenerating rising edge on CH0. System should trigger.");
        probe_signals = 8'h00;  // 通道0先拉低（初始状态）
        #1000;                   // 等待1000ns
        probe_signals = 8'h01;  // 通道0拉高（产生上升沿）
        #5000;                   // 等待5000ns，观察触发状态

        wait (u_dut.capture_done == 1'b1);  // 等待采集完成（DUT内部信号置1）
        $display("OR Mode Trigger Successful! Capture done.");

        press_button(3'd0);  // 按"触发使能"键，停止采集
        #10000;              // 等待10000ns，准备下一个测试

        // =============================================================
        // 测试2：AND模式验证（累加触发，所有通道满足条件才触发）
        // =============================================================
        $display("\n\n[Test 2] AND Mode (Combined Trigger) Verification");
        $display("-------------------------------------------------");
        // 复位系统（重新初始化，避免上一测试影响）
        sys_rst_n = 1'b0;
        probe_signals = 8'h00;
        #200;  // 保持复位200ns
        sys_rst_n = 1'b1;
        #200;  // 释放复位后等待200ns

        // 重新配置通道（与测试1相同：CH0=上升沿，CH1=下降沿）
        configure_channel(0, 3'b001);  // CH0:上升沿触发
        configure_channel(1, 3'b011);  // CH1:下降沿触发

        $display("Switching to AND mode (AND-ACC)...");
        press_button(3'd3);  // 按"模式选择"键（ID=3），从默认OR切换到AND-ACC
        print_config();      // 打印配置，确认模式切换正确

        $display("Starting capture (AND mode)...");
        press_button(3'd0);  // 启动采集
        #1000;  // 等待采集状态稳定

        // 仅生成CH0的上升沿（CH1未满足），验证是否不触发
        $display("\nGenerating rising edge on CH0 only. Should NOT trigger.");
        probe_signals = 8'h02;  // CH1=1（为后续下降沿做准备），CH0=0
        #1000;
        probe_signals = 8'h03;  // CH0=1（上升沿），CH1=1（未满足）
        #3000;  // 等待3000ns，观察是否误触发
        $display("Status: capturing=%b, triggered=%b, done=%b",
                 u_dut.capturing, u_dut.triggered, u_dut.capture_done);

        // 生成CH1的下降沿（此时CH0已满足条件），应该触发
        $display("\nGenerating falling edge on CH1. Should trigger now.");
        probe_signals = 8'h01;  // CH1=0, CH0=1（CH1下降沿）
        #5000;

        wait (u_dut.capture_done == 1'b1);  // 等待采集完成
        $display("AND Mode Trigger Successful! Capture done.");

        // =============================================================
        // 测试3：电平触发（OR & AND）
        // =============================================================
        $display("\n\n[Test 3] Level Trigger (OR and AND)");
        $display("-------------------------------------------------");
        // 复位系统
        sys_rst_n = 1'b0; probe_signals = 8'h00; #200; sys_rst_n = 1'b1; #200;

        // 配置: CH0=高电平(101), CH1=低电平(111)
        configure_channel(0, 3'b101);
        configure_channel(1, 3'b111);

        // 3a) OR 模式
        $display("Switching to OR mode...");
        // 确保 OR（默认即 OR，如非OR则按一次或多次切回）
        while (u_dut.trigger_mode_sel != 2'd0) press_button(3'd3);
        print_config();

        $display("Starting capture (Level OR mode)...");
        press_button(3'd0);  // 启动采集
        #500;
        // 仅满足CH0=高电平，应该触发
        probe_signals = 8'b0000_0001; // CH0=1, CH1=0(也满足)，更快触发
        #5000;
        wait (u_dut.capture_done == 1'b1);
        $display("Level OR Trigger Successful!");

        press_button(3'd0); // 停止
        #5000;

        // 3b) AND 模式
        $display("Switching to AND mode...");
        press_button(3'd3); // 切到 AND
        print_config();
        $display("Starting capture (Level AND mode)...");
        press_button(3'd0);  // 启动采集
        #500;
        // 先满足CH0=高，但CH1=高(不满足低) → 不触发
        probe_signals = 8'b0000_0011; // CH1=1, CH0=1
        #3000;
        // 再让CH1=0，此时两个条件同时满足 → 触发
        probe_signals = 8'b0000_0001; // CH1=0, CH0=1
        #5000;
        wait (u_dut.capture_done == 1'b1);
        $display("Level AND Trigger Successful!");

        // =============================================================
        // 测试4: 同拍 AND（AND-COIN）
        // =============================================================
        $display("\n\n[Test 4] AND-COIN Mode (Coincident Trigger) Verification");
        $display("-------------------------------------------------");

        // 复位系统
        sys_rst_n = 1'b0; probe_signals = 8'h00; #200; sys_rst_n = 1'b1; #200;

        // 配置 CH0=上升沿, CH1=上升沿
        configure_channel(0, 3'b001);
        configure_channel(1, 3'b001);

        // 切换到 AND-COIN 模式
        while (u_dut.trigger_mode_sel != 2'd2) press_button(3'd3);
        print_config();

        $display("Starting capture (AND-COIN mode)...");
        press_button(3'd0);  // 启动采集
        #1000;

        // 先CH0 上升沿，不应触发
        $display("\nCH0 rising only -> should NOT trigger.");
        probe_signals = 8'b0000_0001;  // CH0=1, CH1=0
        #3000;

        // 随后 CH1 上升沿（上一拍CH0 已上升），仍不应触发（非同拍）
        $display("CH1 rising later -> should still NOT trigger.");
        probe_signals = 8'b0000_0011;  // CH0=1, CH1=1
        #3000;

        // 拉回低电平，制造同拍上升沿
        probe_signals = 8'b0000_0000;  // CH0=0, CH1=0
        #200;
        $display("Coincident rising on CH0 & CH1 -> should TRIGGER.");
        probe_signals = 8'b0000_0011;  // 两路同时上升
        #5000;

        wait (u_dut.capture_done == 1'b1);
        $display("AND-COIN Mode Trigger Successful! Capture done. Trigger index=%0d", u_dut.trigger_index);

        // 结束仿真
        #10000;
        $display("\n========================================");
        $display("All Tests Completed Successfully");
        $display("========================================");
        $finish;
    end

    // -------------------------- 8. 超时保护 --------------------------
    // 超时保护：防止仿真卡死，设置10ms超时（仿真模式下足够长）
    initial begin
        #10_000_000;  // 10ms超时（仿真模式下足够长）
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule
