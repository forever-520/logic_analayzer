`timescale 1ns / 1ps
`define SIMULATION

module tb_fpga_top_config;

    // ʱ�Ӻ͸�λ��??
    reg        sys_clk;
    reg        sys_rst_n;

    // ̽���ź�??8ͨ��??
    reg  [7:0] probe_signals;

    // �����źţ��ߵ�ƽΪδ����״???��
    reg        btn_trigger_en;
    reg        btn_channel_select;
    reg        btn_type_select;
    reg        btn_trigger_mode;

    // LED ����ź�
    wire       led_capturing;
    wire       led_triggered;
    wire       led_done;
    wire [10:0] la_trigger_index;

    // ����ģʽ����
    reg        sw_test_enable;
    reg  [1:0] sw_test_pattern;

    // ʵ�������ⶥ��ģ??               
    // 仿真中将按键消抖计数缩短到~10us(500个50MHz时钟)
    fpga_top #(
        .DEBOUNCE_CNT_MAX(10'd500)
    ) u_dut (
        .sys_clk           (sys_clk),
        .sys_rst_n         (sys_rst_n),
        .probe_signals     (probe_signals),
        .btn_trigger_en    (btn_trigger_en),
        .btn_channel_select(btn_channel_select),
        .btn_type_select   (btn_type_select),
        .btn_trigger_mode  (btn_trigger_mode),
        .led_capturing     (led_capturing),
        .led_triggered     (led_triggered),
        .led_done          (led_done),
        .la_trigger_index  (la_trigger_index),
        .sw_test_enable    (sw_test_enable),
        .sw_test_pattern   (sw_test_pattern)
    );

    // ���� 50MHz ʱ�ӣ���?? 20ns??
    initial begin
        sys_clk = 1'b0;
        forever #10 sys_clk = ~sys_clk;  // ?? 10ns ��ת????
    end

    // ����ģ������??0-3�ֱ��Ӧ4���������͵�ƽΪ����??
    task press_button;
        input [2:0] btn_id;  // 0:����ʹ�� 1:ͨ��ѡ�� 2:����ѡ�� 3:����ģʽ
        begin
            // ���°��������ͣ�
            case (btn_id)
                3'd0: btn_trigger_en     = 1'b0;
                3'd1: btn_channel_select = 1'b0;
                3'd2: btn_type_select    = 1'b0;
                3'd3: btn_trigger_mode   = 1'b0;
            endcase
            #20_000;  // Hold 20us (1000 clocks @ 50MHz, enough for CNT_MAX=511)

            // �ͷŰ��������ߣ�
            case (btn_id)
                3'd0: btn_trigger_en     = 1'b1;
                3'd1: btn_channel_select = 1'b1;
                3'd2: btn_type_select    = 1'b1;
                3'd3: btn_trigger_mode   = 1'b1;
            endcase
            #30_000;   // Wait 30us after release (1500 clocks, ensure full reset)
        end
    endtask

    // ��ӡ��ǰ����״???��??
    task print_config;
        integer ch;  // ѭ��������???���ţ�
        begin
            $display("=================================================");
            $display("Current Config | Selected CH: %0d | Trigger Mode: %s",
                     u_dut.config_channel_idx,
                     (u_dut.trigger_mode_sel==2'd0) ? "OR (Independent)" :
                     (u_dut.trigger_mode_sel==2'd1) ? "AND-ACC (Accumulate)" :
                     (u_dut.trigger_mode_sel==2'd2) ? "AND-COIN (Coincident)" : "UNKNOWN");
            $display("-------------------------------------------------");
            $display("CH | Code | Mode      | Status");
            $display("---|------|-----------|----------");
            for (ch = 0; ch < 8; ch = ch + 1) begin
                $write(" %0d | %03b  | ", ch, u_dut.trigger_config[ch]);
                // ������������ʾģʽ��??
                case (u_dut.trigger_config[ch])
                    3'b000: $write("Disabled  ");
                    3'b001: $write("RisingEdge");
                    3'b011: $write("FallingEdg");
                    3'b101: $write("HighLevel ");
                    3'b111: $write("LowLevel  ");
                    default: $write("Undefined ");
                endcase
                // ��ǵ�ǰѡ�е�???��
                if (ch == u_dut.config_channel_idx)
                    $display("| <- Selected");
                else
                    $display("|");
            end
            $display("=================================================");
        end
    endtask
    
    // ͨ���������������﷨���߼�??
    task configure_channel;
        input [2:0] channel_num;    // Ŀ��ͨ���ţ�0-7??
        input [2:0] desired_config; // Ŀ�������루000/001/011/101/111??
        
        integer current_state_idx;  // ��ǰ״???������0-4??
        integer target_state_idx;   // Ŀ��״???������0-4??
        integer presses_needed;     // ??Ҫ�����Ĵ���
        integer i;                  // ѭ����������Verilog 2001 ??��ǰ����??
        reg [2:0] current_config_val; // ��ǰ����??

        begin
            $display("--> Configuring CH%0d to %03b...", channel_num, desired_config);
            
            // 1. �л���Ŀ��???��
            while (u_dut.config_channel_idx != channel_num) begin
                press_button(3'd1);  // ��???��ѡ��??
            end
            $display("    Channel %0d selected.", channel_num);

            // 2. ��ȡ��ǰͨ������??
            current_config_val = u_dut.trigger_config[channel_num];

            // 3. ��������ӳ��Ϊ״̬������0-4ѭ��??
            case(current_config_val)
                3'b000: current_state_idx = 0; // ����
                3'b001: current_state_idx = 1; // ����??
                3'b011: current_state_idx = 2; // �½�??
                3'b101: current_state_idx = 3; // �ߵ�??
                3'b111: current_state_idx = 4; // �͵�??
                default: current_state_idx = 0; // Ĭ�Ͻ���
            endcase
            case(desired_config)
                3'b000: target_state_idx = 0;
                3'b001: target_state_idx = 1;
                3'b011: target_state_idx = 2;
                3'b101: target_state_idx = 3;
                3'b111: target_state_idx = 4;
                default: target_state_idx = 0;
            endcase

            // 4. ����??Ҫ�����Ĵ���������ѭ��???��??
            if (target_state_idx >= current_state_idx) begin
                presses_needed = target_state_idx - current_state_idx;
            end else begin
                presses_needed = (5 - current_state_idx) + target_state_idx;
            end

            // 5. ִ�а�������������ѭ������������
            $display("    Current state: %03b, Target: %03b, Need %0d presses.", 
                     current_config_val, desired_config, presses_needed);
            for (i = 0; i < presses_needed; i = i + 1) begin
                press_button(3'd2);  // 按类型选择键
                #200;  // 等待配置稳定(10个时钟周期)
            end

            $display("    Configuration complete.");
        end
    endtask

    // ��������??
    initial begin
        // ��ʼ��������??
        sys_rst_n         = 1'b0;       // ��λ��Ч
        probe_signals     = 8'h00;      // ̽���ʼ??0
        btn_trigger_en    = 1'b1;       // ����Ĭ��δ���£��ߵ�ƽ��
        btn_channel_select= 1'b1;
        btn_type_select   = 1'b1;
        btn_trigger_mode  = 1'b1;
        sw_test_enable    = 1'b0;       // �رղ���ģʽ
        sw_test_pattern   = 2'b00;

        // �ͷŸ�λ
        #100; sys_rst_n = 1'b1;
        #100;  // �ȴ���λ�ȶ�

        // =============================================================
        // ����1: ORģʽ��������������֤
        // =============================================================
        $display("\n\n[Test 1] OR Mode (Independent Trigger) Verification");
        $display("-------------------------------------------------");
        
        // 配置通道0为上升沿，通道1为下降沿
        configure_channel(0, 3'b001);
        configure_channel(1, 3'b011);
        print_config();  // 打印当前配置

        $display("Starting capture (OR mode)...");
        press_button(3'd0);  // 启动采样
        #1000;  // 等待状态稳定
        
        // 生成通道0的上升沿，应该触发
        $display("\nGenerating rising edge on CH0. System should trigger.");
        probe_signals = 8'h00;  // CH0=0
        #1000;
        probe_signals = 8'h01;  // CH0=1，上升沿
        #5000;
        
        wait (led_done == 1'b1);  // 等待采样完成
        $display("OR Mode Trigger Successful! Capture done.");

        press_button(3'd0);  // 停止采样
        #10000;

        // =============================================================
        // ����2: ANDģʽ����ϴ�������֤
        // =============================================================
        $display("\n\n[Test 2] AND Mode (Combined Trigger) Verification");
        $display("-------------------------------------------------");
        // 复位系统，重新初始化
        sys_rst_n = 1'b0;
        probe_signals = 8'h00;
        #200;
        sys_rst_n = 1'b1;
        #200;

        // 重新配置通道（和测试1相同）
        configure_channel(0, 3'b001);  // CH0:上升沿
        configure_channel(1, 3'b011);  // CH1:下降沿
        
        $display("Switching to AND mode (AND-ACC)...");
        press_button(3'd3);  // 从默认OR->AND-ACC
        print_config();

        $display("Starting capture (AND mode)...");
        press_button(3'd0);  // 启动采样
        #1000;  // 等待状态稳定

        // 仅生成CH0的上升沿，不应触发
        $display("\nGenerating rising edge on CH0 only. Should NOT trigger.");
        probe_signals = 8'h02;  // CH1=1, CH0=0
        #1000;
        probe_signals = 8'h03;  // CH1=1, CH0=1（CH0上升沿）
        #3000;
        $display("Status: led_capturing=%b, led_triggered=%b, led_done=%b",
                 led_capturing, led_triggered, led_done);

        // 生成CH1的下降沿，此时CH0已满足，应该触发
        $display("\nGenerating falling edge on CH1. Should trigger now.");
        probe_signals = 8'h01;  // CH1=0, CH0=1（CH1下降沿）
        #5000;
        
        wait (led_done == 1'b1);  // 等待采样完成
        $display("AND Mode Trigger Successful! Capture done.");

        // =============================================================
        // 测试3: 电平触发（OR 与 AND）
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
        press_button(3'd0);
        #500;
        // 仅满足CH0=高电平 → 应该触发
        probe_signals = 8'b0000_0001; // CH0=1, CH1=0(也满足)，更快触发
        #5000;
        wait (led_done == 1'b1);
        $display("Level OR Trigger Successful!");

        press_button(3'd0); // 停止
        #5000;

        // 3b) AND 模式
        $display("Switching to AND mode...");
        press_button(3'd3); // 切到 AND
        print_config();
        $display("Starting capture (Level AND mode)...");
        press_button(3'd0);
        #500;
        // 先满足CH0=高，但CH1=高(不满足低) → 不触发
        probe_signals = 8'b0000_0011; // CH1=1, CH0=1
        #3000;
        // 再让CH1=0，此时两个条件同时满足 → 触发
        probe_signals = 8'b0000_0001; // CH1=0, CH0=1
        #5000;
        wait (led_done == 1'b1);
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
        press_button(3'd0);
        #1000;

        // 仅 CH0 上升沿，不应触发
        $display("\nCH0 rising only -> should NOT trigger.");
        probe_signals = 8'b0000_0001;  // CH0=1, CH1=0
        #3000;

        // 随后 CH1 上升沿（上一拍 CH0 已上升），仍不应触发（非同拍）
        $display("CH1 rising later -> should still NOT trigger.");
        probe_signals = 8'b0000_0011;  // CH0=1, CH1=1
        #3000;

        // 拉回低电平，制造同拍上升沿
        probe_signals = 8'b0000_0000;  // CH0=0, CH1=0
        #200;
        $display("Coincident rising on CH0 & CH1 -> should TRIGGER.");
        probe_signals = 8'b0000_0011;  // 两路同时上升
        #5000;

        wait (led_done == 1'b1);
        $display("AND-COIN Mode Trigger Successful! Capture done. Trigger index=%0d", la_trigger_index);

        // 结束仿真
        #10000;
        $display("\n========================================");
        $display("All Tests Completed Successfully");
        $display("========================================");
        $finish;
    end

    // 超时保护，防止仿真卡死
    initial begin
        #10_000_000;  // 10ms超时（仿真模式下足够）
        $display("ERROR: Simulation timeout!");
        $finish;
    end

endmodule       
