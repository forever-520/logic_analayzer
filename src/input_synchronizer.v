`timescale 1ns / 1ps
/*
 * 模块名称: input_synchronizer
 * 功能概述: 多比特异步输入同步器。提供 2/3 级可配置同步级数，将外部或不同时钟域的
 *           输入同步到本地 clk 时钟域，降低亚稳态风险。
 *
 * 参数说明:
 * - DATA_WIDTH : 数据位宽。
 * - SYNC_STAGES: 同步级数（2 或 3）。
 *
 * 端口说明:
 * - clk     : 目标时钟域。
 * - rst_n   : 低电平异步复位。
 * - data_in : 待同步的异步输入。
 * - data_out: 同步到 clk 域后的稳定输出。
 */

module input_synchronizer #(
    parameter DATA_WIDTH = 8,
    parameter SYNC_STAGES = 2  // 可配置：2级=快速响应，3级=更稳定
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire [DATA_WIDTH-1:0]    data_in,
    output reg  [DATA_WIDTH-1:0]    data_out
);

    reg [DATA_WIDTH-1:0] sync_ff1;

    generate
        if (SYNC_STAGES == 2) begin
            // 2级同步：延迟2周期，适合稳定信号
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    sync_ff1  <= {DATA_WIDTH{1'b0}};
                    data_out  <= {DATA_WIDTH{1'b0}};
                end else begin
                    sync_ff1  <= data_in;
                    data_out  <= sync_ff1;
                end
            end
        end else begin
            // 3级同步：延迟3周期，更可靠
            reg [DATA_WIDTH-1:0] sync_ff2;
            always @(posedge clk or negedge rst_n) begin
                if (!rst_n) begin
                    sync_ff1  <= {DATA_WIDTH{1'b0}};
                    sync_ff2  <= {DATA_WIDTH{1'b0}};
                    data_out  <= {DATA_WIDTH{1'b0}};
                end else begin
                    sync_ff1  <= data_in;
                    sync_ff2  <= sync_ff1;
                    data_out  <= sync_ff2;
                end
            end
        end
    endgenerate

endmodule
