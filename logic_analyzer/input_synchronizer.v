`timescale 1ns / 1ps

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