`timescale 1ns / 1ps

module uart_tx #(
    parameter integer CLK_FREQ  = 50_000_000,
    parameter integer BAUD_RATE = 115200
)(
    input  wire       clk,
    input  wire       rst_n,

    input  wire [7:0] tx_data,
    input  wire       tx_valid,
    output wire       tx_ready,   // 1=可接收下一个字节

    output reg        uart_tx
);

    localparam integer BAUD_DIV = CLK_FREQ / BAUD_RATE;
    localparam integer BAUD_CNT_W = $clog2(BAUD_DIV);

    reg [BAUD_CNT_W-1:0] baud_cnt;
    reg baud_tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            baud_cnt  <= 0;
            baud_tick <= 1'b0;
        end else begin
            if (baud_cnt == BAUD_DIV-1) begin
                baud_cnt  <= 0;
                baud_tick <= 1'b1;
            end else begin
                baud_cnt  <= baud_cnt + 1'b1;
                baud_tick <= 1'b0;
            end
        end
    end

    // FSM
    localparam S_IDLE  = 2'd0;
    localparam S_START = 2'd1;
    localparam S_DATA  = 2'd2;
    localparam S_STOP  = 2'd3;

    reg [1:0] state;
    reg [2:0] bit_idx;
    reg [7:0] shifter;

    assign tx_ready = (state == S_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= S_IDLE;
            bit_idx <= 3'd0;
            shifter <= 8'h00;
            uart_tx <= 1'b1; // idle high
        end else begin
            case (state)
                S_IDLE: begin
                    uart_tx <= 1'b1;
                    if (tx_valid) begin
                        shifter <= tx_data;
                        bit_idx <= 3'd0;
                        state   <= S_START;
                    end
                end
                S_START: begin
                    // start bit = 0
                    uart_tx <= 1'b0;
                    if (baud_tick) begin
                        state <= S_DATA;
                    end
                end
                S_DATA: begin
                    uart_tx <= shifter[0];
                    if (baud_tick) begin
                        shifter <= {1'b0, shifter[7:1]};
                        if (bit_idx == 3'd7) begin
                            state <= S_STOP;
                        end else begin
                            bit_idx <= bit_idx + 1'b1;
                        end
                    end
                end
                S_STOP: begin
                    // stop bit = 1
                    uart_tx <= 1'b1;
                    if (baud_tick) begin
                        state <= S_IDLE;
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

