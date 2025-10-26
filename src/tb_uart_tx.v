`timescale 1ns / 1ps

module tb_uart_tx;
    localparam CLK_FREQ  = 50_000_000;
    localparam BAUD_RATE = 115200;
    localparam integer BAUD_DIV = CLK_FREQ / BAUD_RATE;

    reg clk;
    reg rst_n;
    reg [7:0] tx_data;
    reg       tx_valid;
    wire      tx_ready;
    wire      uart_tx;

    uart_tx #(
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) uut (
        .clk(clk),
        .rst_n(rst_n),
        .tx_data(tx_data),
        .tx_valid(tx_valid),
        .tx_ready(tx_ready),
        .uart_tx(uart_tx)
    );

    // 50MHz
    initial clk = 0;
    always #10 clk = ~clk;

    // 简单 UART 接收监视（在比特中心采样）
    task uart_rx_byte;
        output [7:0] b;
        integer i;
        begin
            // 等待起始位
            @(negedge uart_tx);
            // 等半个比特到中心
            #( (BAUD_DIV*20)/2 ); // 20ns per clk -> ticks to time
            for (i=0; i<8; i=i+1) begin
                #(BAUD_DIV*20);
                b[i] = uart_tx;
            end
            // 停止位延时
            #(BAUD_DIV*20);
        end
    endtask

    reg [7:0] rx;

    initial begin
        rst_n = 0; tx_data = 8'h00; tx_valid = 0;
        #200; rst_n = 1;

        // 发送 “A5 5A 00 FF”
        @(posedge clk);
        wait(tx_ready); tx_data=8'hA5; tx_valid=1; @(posedge clk); tx_valid=0;
        wait(tx_ready); tx_data=8'h5A; tx_valid=1; @(posedge clk); tx_valid=0;
        wait(tx_ready); tx_data=8'h00; tx_valid=1; @(posedge clk); tx_valid=0;
        wait(tx_ready); tx_data=8'hFF; tx_valid=1; @(posedge clk); tx_valid=0;

        // 接收打印
        uart_rx_byte(rx); $display("RX=%02h", rx);
        uart_rx_byte(rx); $display("RX=%02h", rx);
        uart_rx_byte(rx); $display("RX=%02h", rx);
        uart_rx_byte(rx); $display("RX=%02h", rx);

        #100000; $finish;
    end
endmodule

