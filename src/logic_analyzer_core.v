`timescale 1ns / 1ps
/*
 * 模块名称: logic_analyzer_core
 * 功能概述: 逻辑分析仪采样核心。以环形方式将 sample_data 写入 BRAM，支持逐位
 *           电平/边沿触发与三种触发模式（OR/AND-累积/AND-同拍）。触发后继续采集
 *           固定数量的后触发样本，输出关键状态与触发地址。
 *
 * 参数说明:
 * - DATA_WIDTH           : 采样数据位宽。
 * - ADDR_WIDTH           : 地址位宽（深度=2^ADDR_WIDTH）。
 * - POST_TRIGGER_SAMPLES : 触发后继续采样的点数（默认=深度/2）。
 *
 * 端口说明:
 * - clk, rst_n          : 时钟与低有效复位。
 * - sample_data[W-1:0]  : 待采样数据（已同步到 clk 域）。
 * - trigger_enable      : 运行/停止（1=布防、0=撤防）。
 * - trigger_value[W-1:0]: 保留接口（值比较，当前未使用）。
 * - trigger_mask[W-1:0] : 逐位触发使能。
 * - edge_trigger[W-1:0] : 逐位 1=边沿、0=电平。
 * - trigger_type[W-1:0] : 边沿(0上升/1下降) 或 电平(0高/1低)。
 * - trigger_mode[1:0]   : 00=OR；01=AND-ACC（边沿事件锁存+电平实时）；10=AND-COIN（同拍）。
 * - trigger_mode_is_or  : 兼容旧接口（未连 trigger_mode 时回退）。
 * - capturing           : 采样中标志。
 * - triggered           : 已触发标志（触发瞬间置位）。
 * - capture_done        : 采样完成标志（进入 DONE）。
 * - trigger_index[A-1:0]: 触发发生时的写地址（用于还原触发点）。
 * - wr_en, wr_addr, wr_data: BRAM 写口。
 */

module logic_analyzer_core #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 11,  // 2^ADDR_WIDTH deep
    // post-trigger samples to capture after the trigger fires
    // default to half of the buffer depth
    parameter integer POST_TRIGGER_SAMPLES = (1<<ADDR_WIDTH)/2
)(
    input  wire                     clk,
    input  wire                     rst_n,

    // 采样数据输入
    input  wire [DATA_WIDTH-1:0]    sample_data,

    // 控制信号
    input  wire                     trigger_enable,  // 触发使能
    input  wire [DATA_WIDTH-1:0]    trigger_value,   // 触发值
    input  wire [DATA_WIDTH-1:0]    trigger_mask,    // 触发掩码 (1=比较, 0=忽略)
    input  wire [DATA_WIDTH-1:0]    edge_trigger,    // 每位：1=边沿触发, 0=电平触发
    input  wire [DATA_WIDTH-1:0]    trigger_type,    // 每位：1=上升沿/高电平, 0=下降沿/低电平
    // 触发模式：00=OR, 01=AND-accumulate, 10=AND-coincident
    // 兼容旧接口：未连接 trigger_mode 时使用 trigger_mode_is_or
    input  wire [1:0]               trigger_mode,
    input  wire                     trigger_mode_is_or,
    input  wire                     trigger_config_changed,  // Fix #3: Clear edge latch on config change
    input  wire                     clear_done,              // 外部请求清除 DONE 状态，回到 WAIT_TRIGGER

    // 状态输出
    output reg                      capturing,       // 正在采样
    output reg                      triggered,       // 已触发
    output reg                      capture_done,    // 采样完成
    output reg  [ADDR_WIDTH-1:0]    trigger_index,   // 记录触发时刻对应的写地址

    // BRAM写接口
    output reg                      wr_en,
    output reg  [ADDR_WIDTH-1:0]    wr_addr,
    output reg  [DATA_WIDTH-1:0]    wr_data
);

    // 状态机定义
    localparam IDLE          = 3'd0;
    localparam WAIT_TRIGGER  = 3'd1;
    localparam POST_CAPTURE  = 3'd2;
    localparam DONE          = 3'd3;

    reg [2:0] state;
    reg [ADDR_WIDTH-1:0] post_cnt;     // after-trigger counter
    reg [DATA_WIDTH-1:0] sample_data_d1;  // 用于边沿检测
    reg [DATA_WIDTH-1:0] edge_triggered_latch;  // 记录哪些边沿已触发（AND模式用）

    // 每位独立的触发检测逻辑
    wire [DATA_WIDTH-1:0] bit_trigger_detected;

    genvar i;
    generate
        for (i = 0; i < DATA_WIDTH; i = i + 1) begin : gen_bit_trigger
            // 边沿检测
            wire pos_edge = (sample_data[i] == 1'b1) && (sample_data_d1[i] == 1'b0);
            wire neg_edge = (sample_data[i] == 1'b0) && (sample_data_d1[i] == 1'b1);

            // 电平检测
            wire high_level = (sample_data[i] == 1'b1);
            wire low_level  = (sample_data[i] == 1'b0);

            // 每位独立判断：边沿模式或电平模式
            // trigger_mask[i]: 1=启用此位, 0=禁用
            // edge_trigger[i]: 1=边沿触发, 0=电平触发
            // trigger_type[i]: 边沿模式(0=上升沿,1=下降沿); 电平模式(0=高电平,1=低电平)
            assign bit_trigger_detected[i] = trigger_mask[i] && (
                edge_trigger[i] ?
                    (trigger_type[i] ? neg_edge : pos_edge) :      // 边沿触发：1=下降沿，0=上升沿
                    (trigger_type[i] ? low_level : high_level)     // 电平触发：1=低电平，0=高电平
            );
        end
    endgenerate

    // 触发模式选择：
    // OR：任意使能通道满足条件即触发
    // AND-accumulate：所有使能通道都必须满足；边沿事件允许先后发生（锁存），电平为实时
    // AND-coincident：所有使能通道在同一拍同时满足（不锁存）
    wire [DATA_WIDTH-1:0] enabled_channels = trigger_mask;  // 使能的通道

    // AND模式：
    // - 对边沿触发位：使用锁存，使不同通道的“事件”可先后发生
    // - 对电平触发位：不锁存，实时要求当前电平满足
    wire [DATA_WIDTH-1:0] edge_status  = edge_triggered_latch & edge_trigger;      // 仅保留边沿位的锁存状态
    wire [DATA_WIDTH-1:0] level_status = bit_trigger_detected & ~edge_trigger;      // 电平位用当前检测结果
    wire [DATA_WIDTH-1:0] and_mode_status = edge_status | level_status;
    wire all_enabled_triggered_acc = &(and_mode_status | ~enabled_channels);
    wire any_enabled_triggered     = |bit_trigger_detected;
    wire all_enabled_triggered_co  = &(bit_trigger_detected | ~enabled_channels);

    // Fix #4: Remove buggy legacy mode detection logic
    // Direct use of trigger_mode (trigger_mode_is_or kept for backward compatibility but not used)
    wire trigger_detected = (trigger_mode == 2'd0) ? any_enabled_triggered :
                            (trigger_mode == 2'd1) ? all_enabled_triggered_acc :
                            /*2'd2 or default*/      all_enabled_triggered_co;

    // 主状态机
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state         <= IDLE;
            capturing     <= 1'b0;
            triggered     <= 1'b0;
            capture_done  <= 1'b0;
            wr_en         <= 1'b0;
            wr_addr       <= 0;
            wr_data       <= 0;
            post_cnt      <= 0;
            sample_data_d1<= 0;
            edge_triggered_latch <= 0;
            trigger_index <= 0;
        end else begin
            sample_data_d1 <= sample_data;

            case (state)
                IDLE: begin
                    capturing    <= 1'b0;
                    triggered    <= 1'b0;
                    capture_done <= 1'b0;
                    wr_en        <= 1'b0;
                    wr_addr      <= 0;
                    post_cnt     <= 0;
                    edge_triggered_latch <= 0;  // 复位边沿锁存

                    if (trigger_enable) begin
                        state     <= WAIT_TRIGGER;
                        capturing <= 1'b1;
                    end
                end

                WAIT_TRIGGER: begin
                    // 持续采样，环形写入（wr_addr按位宽自然回绕）
                    wr_en   <= 1'b1;
                    wr_data <= sample_data;

                    // Fix #3: Clear edge latch when trigger config changes
                    if (trigger_config_changed) begin
                        edge_triggered_latch <= 0;
                    end
                    // AND-accumulate：仅对"边沿触发"的位进行事件锁存
                    else if (trigger_mode == 2'd1) begin
                        edge_triggered_latch <= edge_triggered_latch | (bit_trigger_detected & edge_trigger);
                    end

                    if (trigger_detected) begin
                        state     <= POST_CAPTURE;
                        triggered <= 1'b1;
                        // Fix #2: Record current wr_addr as trigger location
                        trigger_index <= wr_addr;
                        post_cnt <= {ADDR_WIDTH{1'b0}};
                    end

                    // Update address after recording trigger_index
                    wr_addr <= wr_addr + 1'b1;

                    if (!trigger_enable) begin
                        state <= IDLE;
                        edge_triggered_latch <= 0;  // Clear latch when returning to IDLE
                    end
                end

                POST_CAPTURE: begin
                    // 触发后继续采样固定数量（POST_TRIGGER_SAMPLES）
                    wr_en   <= 1'b1;
                    wr_data <= sample_data;
                    // Fix: Explicit address wraparound (though natural wraparound should work)
                    wr_addr <= wr_addr + 1'b1;  // Address width limits automatic wraparound
                    post_cnt <= post_cnt + 1'b1;

                    if (post_cnt == POST_TRIGGER_SAMPLES-1) begin
                        state <= DONE;
                    end

                    if (!trigger_enable) begin
                        state <= IDLE;
                        edge_triggered_latch <= 0;  // Clear latch when returning to IDLE
                    end
                end

                DONE: begin
                    wr_en        <= 1'b0;
                    capturing    <= 1'b0;
                    capture_done <= 1'b1;  // 保持高电平，直到外部清除

                    if (!trigger_enable) begin
                        // 停止模式：回到 IDLE
                        state <= IDLE;
                        edge_triggered_latch <= 0;
                    end else if (clear_done) begin
                        // 连续模式：外部（uart_done）触发清除，回到 WAIT_TRIGGER
                        state <= WAIT_TRIGGER;
                        triggered    <= 1'b0;
                        capture_done <= 1'b0;
                        edge_triggered_latch <= 0;
                    end
                end

                default: state <= IDLE;
            endcase
        end
    end

endmodule
