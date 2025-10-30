`timescale 1ns / 1ps
/*
 * 模块名称: fpga_top
 * 功能概述: 顶层集成。完成外部按键消抖、触发条件的人机配置、采样核心与 BRAM 的
 *           连接，提供可选片上测试信号发生器，并在非仿真下连接 ILA 便于调试。
 *           采样数据源可在外部探针与内部测试信号之间切换。
 *
 * 参数说明:
 * - DEBOUNCE_CNT_MAX: 按键消抖计数阈值（默认约 20ms@50MHz；仿真中可缩短）。
 *
 * 端口说明:
 * - sys_clk, sys_rst_n: 系统时钟与低有效复位。
 * - probe_signals[7:0]: 外部 8 路被测信号（异步，内部同步）。
 * - btn_trigger_en     : 运行/停止切换按键（低有效，消抖后单拍）。
 * - btn_channel_select : 触发配置通道选择按键。
 * - btn_type_select    : 当前通道触发类型循环按键（关/上升/下降/高/低）。
 * - btn_trigger_mode   : 触发模式轮换（OR/AND-ACC/AND-COIN）。
 * - led_capturing      : 采样中指示。
 * - led_triggered      : 已触发指示。
 * - led_done           : 采样完成指示。
 * - la_trigger_index[10:0]: 触发地址导出。
 * - sw_test_enable     : 1=采样内部测试信号，0=采样外部 probe_signals。
 * - sw_test_pattern[1:0]: 测试信号模式选择。
 */

module fpga_top #(
    // Debounce counter max. Default ~20ms @50MHz
    // In simulation, override in the testbench, e.g. 10'd500 (~10us)
    parameter integer DEBOUNCE_CNT_MAX = 20'd999_999
)(
    // System clock and reset
    input  wire        sys_clk,
    input  wire        sys_rst_n,   // active low

    // External probe signals (8 channels)
    input  wire [7:0]  probe_signals,

    // Push buttons (active low level into debounce, pulse out)
    input  wire        btn_trigger_en,
    input  wire        btn_channel_select,
    input  wire        btn_type_select,
    input  wire        btn_trigger_mode,

    // Optional test signal generator control
    input  wire        sw_test_enable,
    input  wire [1:0]  sw_test_pattern
);

    // Internal signals
    wire [7:0] probe_sync;
    wire [7:0] test_signals;
    wire [7:0] sample_data;

    wire btn_trigger_pulse;
    wire btn_channel_pulse;
    wire btn_type_pulse;
    wire btn_mode_pulse;

    reg  trigger_enable_state;      // 1=run, 0=stop
    reg  [1:0] trigger_mode_sel;    // 00=OR, 01=AND-ACC, 10=AND-COIN
    reg  [2:0] config_channel_idx;  // 0..7
    reg  [2:0] trigger_config [0:7];// per-channel 3-bit code

    // 3-bit code definition per channel:
    // bit2: 0=edge, 1=level
    // bit1: polarity (edge: 0=rising,1=falling; level: 0=high,1=low)
    // bit0: enable (1=enable,0=disable)

    // Decode to per-bit masks and types
    wire [7:0] trigger_mask;       // enable mask
    wire [7:0] edge_trigger_mode;  // 1=edge, 0=level
    wire [7:0] trigger_type;       // polarity per bit

    genvar i;
    generate
        for (i = 0; i < 8; i = i + 1) begin : gen_decode
            assign trigger_mask[i]      = trigger_config[i][0];
            assign edge_trigger_mode[i] = ~trigger_config[i][2];
            assign trigger_type[i]      = trigger_config[i][1];
        end
    endgenerate

    // 当前选中通道的触发配置（仅用于 ILA 观测）：
    // 3'b[2:0] = {level_or_edge(0=edge,1=level), polarity(0:rise/high,1:fall/low), enable}
    wire [2:0] curr_trig_cfg = trigger_config[config_channel_idx];
    wire [7:0] curr_trig_cfg_ext = {5'b0, curr_trig_cfg};

    wire        wr_en;
    wire [10:0] wr_addr;
    wire [7:0]  wr_data;

    wire        capturing;
    wire        triggered;
    wire        capture_done;
    wire [10:0] trigger_index;

    // Select sample source
    assign sample_data = sw_test_enable ? test_signals : probe_sync;

    // Run/stop toggle
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            trigger_enable_state <= 1'b0;
        end else if (btn_trigger_pulse) begin
            trigger_enable_state <= ~trigger_enable_state;
        end
    end

    // Trigger mode cycle: OR -> AND-ACC -> AND-COIN
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            trigger_mode_sel <= 2'd0; // OR
        end else if (btn_mode_pulse) begin
            if (trigger_mode_sel == 2'd2)
                trigger_mode_sel <= 2'd0;
            else
                trigger_mode_sel <= trigger_mode_sel + 1'b1;
        end
    end

    // Channel selection 0..7
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            config_channel_idx <= 3'd0;
        end else if (btn_channel_pulse) begin
            if (config_channel_idx == 3'd7)
                config_channel_idx <= 3'd0;
            else
                config_channel_idx <= config_channel_idx + 1'b1;
        end
    end

    // Type selection state: 000(disable)->001(rise)->011(fall)->101(high)->111(low)->000
    always @(posedge sys_clk or negedge sys_rst_n) begin
        if (!sys_rst_n) begin
            trigger_config[0] <= 3'b000;
            trigger_config[1] <= 3'b000;
            trigger_config[2] <= 3'b000;
            trigger_config[3] <= 3'b000;
            trigger_config[4] <= 3'b000;
            trigger_config[5] <= 3'b000;
            trigger_config[6] <= 3'b000;
            trigger_config[7] <= 3'b000;
        end else if (btn_type_pulse) begin
            case (trigger_config[config_channel_idx])
                3'b000:  trigger_config[config_channel_idx] <= 3'b001;
                3'b001:  trigger_config[config_channel_idx] <= 3'b011;
                3'b011:  trigger_config[config_channel_idx] <= 3'b101;
                3'b101:  trigger_config[config_channel_idx] <= 3'b111;
                3'b111:  trigger_config[config_channel_idx] <= 3'b000;
                default: trigger_config[config_channel_idx] <= 3'b000;
            endcase
        end
    end

    // Input synchronizer
    input_synchronizer #(
        .DATA_WIDTH(8)
    ) u_input_sync (
        .clk(sys_clk),
        .rst_n(sys_rst_n),
        .data_in(probe_signals),
        .data_out(probe_sync)
    );

    // Debounce: output single-cycle pulse
    debounce #(.CNT_MAX(DEBOUNCE_CNT_MAX)) u_debounce_trigger (
        .clk(sys_clk),
        .rst_n(sys_rst_n),
        .btn_in(btn_trigger_en),
        .btn_flag(btn_trigger_pulse)
    );

    debounce #(.CNT_MAX(DEBOUNCE_CNT_MAX)) u_debounce_channel (
        .clk(sys_clk),
        .rst_n(sys_rst_n),
        .btn_in(btn_channel_select),
        .btn_flag(btn_channel_pulse)
    );

    debounce #(.CNT_MAX(DEBOUNCE_CNT_MAX)) u_debounce_type (
        .clk(sys_clk),
        .rst_n(sys_rst_n),
        .btn_in(btn_type_select),
        .btn_flag(btn_type_pulse)
    );

    debounce #(.CNT_MAX(DEBOUNCE_CNT_MAX)) u_debounce_mode (
        .clk(sys_clk),
        .rst_n(sys_rst_n),
        .btn_in(btn_trigger_mode),
        .btn_flag(btn_mode_pulse)
    );

    // Logic analyzer core
    logic_analyzer_core #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(11)
    ) u_la_core (
        .clk(sys_clk),
        .rst_n(sys_rst_n),
        .sample_data(sample_data),
        .trigger_enable(trigger_enable_state),
        .trigger_value(8'h00),
        .trigger_mask(trigger_mask),
        .edge_trigger(edge_trigger_mode),
        .trigger_type(trigger_type),
        .trigger_mode(trigger_mode_sel),
        .trigger_mode_is_or(trigger_mode_sel[0]), // legacy compatible
        .capturing(capturing),
        .triggered(triggered),
        .capture_done(capture_done),
        .trigger_index(trigger_index),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data)
    );

    // BRAM sample buffer
    sample_buffer #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(11)
    ) u_sample_buffer (
        .wr_clk(sys_clk),
        .wr_en(wr_en),
        .wr_addr(wr_addr),
        .wr_data(wr_data),
        .rd_clk(sys_clk),
        .rd_addr(11'd0),
        .rd_data()
    );

    // Test signal generator (optional)
    test_signal_gen #(
        .DATA_WIDTH(8)
    ) u_test_gen (
        .clk(sys_clk),
        .rst_n(sys_rst_n),
        .enable(sw_test_enable),
        .pattern_sel(sw_test_pattern),
        .test_data(test_signals)
    );

`ifndef SIMULATION
    // Integrated Logic Analyzer (ILA) for on-chip debug
    // IP name: ila  (generated by Vivado). Probes mapping follows ila.veo template.
    ila u_ila_la (
        .clk(sys_clk),

        .probe0 (sample_data),          // [7:0]
        .probe1 (wr_en),                // [0:0]
        .probe2 (wr_addr),              // [10:0]
        .probe3 (wr_data),              // [7:0]
        .probe4 (capturing),            // [0:0]
        .probe5 (triggered),            // [0:0]
        .probe6 (capture_done),         // [0:0]
        .probe7 (trigger_index),        // [10:0]
        .probe8 (trigger_enable_state), // [0:0]
        .probe9 (trigger_mode_sel),     // [1:0]    
        .probe10(config_channel_idx),   // [2:0]
        .probe11(btn_trigger_pulse),    // [0:0]
        .probe12(btn_channel_pulse),    // [0:0]
        .probe13(btn_type_pulse),       // [0:0]
        .probe14(btn_mode_pulse),       // [0:0]
        // 将 probe15 用于显示“当前通道的触发配置”
        // bit2: 0=边沿/1=电平；bit1: 极性；bit0: 使能
        .probe15(curr_trig_cfg_ext),    // [7:0] 显示为 {5'b0, 3'bcfg}
        .probe16(sw_test_enable),       // [0:0]
        .probe17(sw_test_pattern)       // [1:0]
    );
`endif

endmodule
