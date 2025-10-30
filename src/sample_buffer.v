`timescale 1ns / 1ps
/*
 * 模块名称: sample_buffer
 * 功能概述: 同步双端口 BRAM 缓冲。写端用于采样写入，读端用于调试/导出读取；
 *           深度为 2^ADDR_WIDTH，读口同步并在时钟上升沿输出寄存。
 *
 * 参数说明:
 * - DATA_WIDTH: 每个样本的位宽。
 * - ADDR_WIDTH: BRAM 地址宽度（深度=2^ADDR_WIDTH）。
 *
 * 端口说明:
 * - wr_clk, wr_en, wr_addr, wr_data: 写端口（采样侧）。
 * - rd_clk, rd_addr, rd_data       : 读端口（观测/导出侧）。
 */

module sample_buffer #(
    parameter DATA_WIDTH = 8,
    parameter ADDR_WIDTH = 11  // 2048深度
)(
    // 写端口 (采样侧)
    input  wire                     wr_clk,
    input  wire                     wr_en,
    input  wire [ADDR_WIDTH-1:0]    wr_addr,
    input  wire [DATA_WIDTH-1:0]    wr_data,

    // 读端口 (ILA观测侧)
    input  wire                     rd_clk,
    input  wire [ADDR_WIDTH-1:0]    rd_addr,
    output reg  [DATA_WIDTH-1:0]    rd_data
);

    // BRAM存储
    (* ram_style = "block" *)
    reg [DATA_WIDTH-1:0] ram [0:(1<<ADDR_WIDTH)-1];

    // 写端口
    always @(posedge wr_clk) begin
        if (wr_en) begin
            ram[wr_addr] <= wr_data;
        end
    end

    // 读端口
    always @(posedge rd_clk) begin
        rd_data <= ram[rd_addr];
    end

endmodule
