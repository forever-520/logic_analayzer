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
        .rate_sel(3'd0),
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

    // Header verification and payload check (7-byte header)
    localparam integer DEPTH = (1<<ADDR_W);
    localparam [15:0] LEN16  = (16'd1<<ADDR_W);
    wire [15:0] trig16 = { {(16-ADDR_W){1'b0}}, trigger_index };

    reg [7:0] hdr [0:6];
    reg [7:0] payload_byte;
    integer k;

    initial begin
        // Wait a moment then receive one full frame
        #1000;

        // Receive 7-byte header: 55 AA len_l len_h rate_sel trig_l trig_h
        for (k=0; k<7; k=k+1) begin
            uart_rx_byte(hdr[k]);
        end
        $display("\nHeader = %02h %02h %02h %02h %02h %02h %02h",
                 hdr[0],hdr[1],hdr[2],hdr[3],hdr[4],hdr[5],hdr[6]);

        if (hdr[0]!==8'h55 || hdr[1]!==8'hAA ||
            hdr[2]!==LEN16[7:0] || hdr[3]!==LEN16[15:8] ||
            hdr[4]!==8'h00 || // rate_sel = 3'd0
            hdr[5]!==trig16[7:0] || hdr[6]!==trig16[15:8]) begin
            $fatal(1,
                "Header mismatch: got %02h %02h %02h %02h %02h %02h %02h, exp 55 AA %02h %02h 00 %02h %02h",
                hdr[0],hdr[1],hdr[2],hdr[3],hdr[4],hdr[5],hdr[6],
                LEN16[7:0],LEN16[15:8],trig16[7:0],trig16[15:8]);
        end

        // Receive and verify payload bytes: expected 0..DEPTH-1
        for (k=0; k<DEPTH; k=k+1) begin
            uart_rx_byte(payload_byte);
            if (payload_byte !== k[7:0]) begin
                $fatal(1, "Payload mismatch at %0d: got %02h exp %02h",
                       k, payload_byte, k[7:0]);
            end
        end
        $display("\nFrame verified OK (LEN=%0d, trig=%0d, rate_sel=0)", DEPTH, trigger_index);
    end

endmodule
