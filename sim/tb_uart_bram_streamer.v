`timescale 1ns / 1ps
/*
 * 测试平台: tb_uart_bram_streamer
 * 功能概述: 将 BRAM 中的整帧数据通过 UART 打包发送（含长度与触发地址），
 *           测试端实现了简单 UART 接收器并以十六进制打印。
 * 能否展示“存储后的数据”: 可以。该仿真先向 RAM 预写 0..DEPTH-1，随后经 UART 打印出来，
 *                         可视为“展示缓冲中已存储的数据”的示例路径。
 */
module tb_uart_bram_streamer;
    localparam CLK_FREQ  = 50_000_000;
    localparam BAUD_RATE = 115200;
    localparam ADDR_W    = 4;   // 16 bytes for quick sim

    reg clk;
    reg rst_n;

    // BRAM model: reuse sample_buffer
    wire                   wr_clk = clk;
    reg                    wr_en;
    reg  [ADDR_W-1:0]      wr_addr;
    reg  [7:0]             wr_data;
    wire                   rd_clk = clk;
    wire [ADDR_W-1:0]      rd_addr;
    wire [7:0]             rd_data;

    sample_buffer #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(ADDR_W)
    ) u_ram (
        .wr_clk(wr_clk), .wr_en(wr_en), .wr_addr(wr_addr), .wr_data(wr_data),
        .rd_clk(rd_clk), .rd_addr(rd_addr), .rd_data(rd_data)
    );

    reg                    start;
    wire                   busy;
    wire                   done;
    wire                   uart_tx;
    reg  [ADDR_W-1:0]      trigger_index;

    uart_bram_streamer #(
        .DATA_WIDTH(8),
        .ADDR_WIDTH(ADDR_W),
        .CLK_FREQ(CLK_FREQ),
        .BAUD_RATE(BAUD_RATE)
    ) uut (
        .clk(clk), .rst_n(rst_n),
        .start(start), .busy(busy), .done(done),
        .trigger_index(trigger_index),
        .rd_addr(rd_addr), .rd_data(rd_data),
        .uart_tx(uart_tx)
    );

    // clock
    initial clk=0; always #10 clk=~clk; // 50MHz

    // preload RAM with 0..DEPTH-1
    integer i;
    initial begin
        rst_n = 0; start = 0; wr_en = 0; wr_addr = 0; wr_data = 0; trigger_index = 0;
        #200; rst_n = 1;
        @(posedge clk);
        for (i=0; i<(1<<ADDR_W); i=i+1) begin
            wr_en   <= 1'b1;
            wr_addr <= i[ADDR_W-1:0];
            wr_data <= i[7:0];
            @(posedge clk);
        end
        wr_en <= 1'b0;

        // set trigger index to 6 (arbitrary)
        trigger_index <= 6;

        // start streaming
        repeat(10) @(posedge clk);
        start <= 1'b1; @(posedge clk); start <= 1'b0;

        wait(done);
        #100000; $finish;
    end

    // simple UART receiver to dump bytes
    localparam integer BAUD_DIV = CLK_FREQ / BAUD_RATE;
    task uart_rx_byte;
        output [7:0] b;
        integer j;
        begin
            @(negedge uart_tx);
            #( (BAUD_DIV*20)/2 );
            for (j=0; j<8; j=j+1) begin
                #(BAUD_DIV*20); b[j] = uart_tx; end
            #(BAUD_DIV*20);
        end
    endtask

    reg [7:0] r;
    initial begin
        // Wait some time then start receiving stream
        #1000;
        forever begin
            uart_rx_byte(r);
            $write("%02h ", r);
        end
    end

endmodule
