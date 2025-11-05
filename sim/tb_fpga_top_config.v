`timescale 1ns / 1ps
`define SIMULATION

// ----------------------------------------------------------------------------
// Testbench: tb_fpga_top_config (Vivado compatible, ASCII-only comments)
// - TB switches: default enable on-chip test signal (sw_test_enable=1)
// - UART monitor: prints to console and file uart_dump.log
// - Verilog-2001 compatible: pure Verilog, no SystemVerilog features
// - Observes internal signals via sw_test_pattern selection
// ----------------------------------------------------------------------------
module tb_fpga_top_config;

    // 1) Clock & reset
    reg        sys_clk;
    reg        sys_rst_n;   // active low

    // 2) DUT I/O
    reg  [7:0] probe_signals;   // Kept for compatibility, tied to 0
    reg        btn_trigger_en;
    reg        btn_channel_select;
    reg        btn_type_select;
    reg        btn_trigger_mode;
    reg        sw_test_enable;
    reg  [1:0] sw_test_pattern;

    // 3) UART output
    wire       uart_tx;

    // 4) TB switches & logs
    localparam TB_ENABLE_TEST_MODE_DFLT = 1; // default use on-chip test signals
    reg        tb_use_test_mode;
    reg  [1:0] tb_test_pattern;
    integer    uart_log;
    integer    wait_ns; // TB helper for guarded waits
    // header parse scratch
    reg [15:0] frame_len_chk;
    reg [15:0] trig_idx_chk;

    // DUT (short debounce for sim)
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
        .sw_test_enable    (sw_test_enable),
        .sw_test_pattern   (sw_test_pattern),
        .uart_tx           (uart_tx)
    );

    // ---------------- Clock ----------------
    initial begin
        sys_clk = 1'b0;
        forever #10 sys_clk = ~sys_clk; // 50 MHz
    end

    // ---------------- Logging ----------------
    initial begin
        tb_use_test_mode = TB_ENABLE_TEST_MODE_DFLT;
        tb_test_pattern  = 2'b01; // internal_bus0 (status + write address)
        if ($test$plusargs("USE_TEST")) tb_use_test_mode = 1'b1;
        if ($value$plusargs("TEST_PAT=%d", tb_test_pattern)) begin end

        uart_log = $fopen("uart_dump.log", "w");
        $display("[TB] Logging to uart_dump.log");
    end

    // ---------------- Tasks ----------------
    // Simulated buttons: 0=trigger_en, 1=channel_select, 2=type_select, 3=mode_select
    task automatic press_button;
        input [2:0] btn_id;
        begin
            case (btn_id)
                3'd0: btn_trigger_en     = 1'b0;
                3'd1: btn_channel_select = 1'b0;
                3'd2: btn_type_select    = 1'b0;
                3'd3: btn_trigger_mode   = 1'b0;
            endcase
            #20_000; // 20 us > debounce
            case (btn_id)
                3'd0: btn_trigger_en     = 1'b1;
                3'd1: btn_channel_select = 1'b1;
                3'd2: btn_type_select    = 1'b1;
                3'd3: btn_trigger_mode   = 1'b1;
            endcase
            #30_000; // settle time after release
        end
    endtask

    // Print current configuration snapshot
    task automatic print_config;
        integer ch;
        begin
            $display("=================================================");
            $display("Current Config | Selected CH: %0d | Trigger Mode: %0d",
                     u_dut.config_channel_idx, u_dut.trigger_mode_sel);
            $display("CH | Code");
            for (ch = 0; ch < 8; ch = ch + 1) begin
                $display(" %0d | %03b %s", ch, u_dut.trigger_config[ch],
                         (ch==u_dut.config_channel_idx)?"<- Selected":"");
            end
            $display("=================================================");
        end
    endtask

    // Configure a channel to desired 3-bit code: 000/001/011/101/111
    task automatic configure_channel;
        input [2:0] channel_num;
        input [2:0] desired_config;
        integer current_state_idx, target_state_idx;
        integer presses_needed, i, guard;
        reg [2:0] current_config_val;
        begin
            // select channel with guard
            guard = 0;
            while (u_dut.config_channel_idx != channel_num && guard < 16) begin
                press_button(3'd1);
                guard = guard + 1;
            end
            if (u_dut.config_channel_idx != channel_num) begin
                $display("[TB] ERROR: Failed to select channel %0d", channel_num);
                $stop;
            end
            current_config_val = u_dut.trigger_config[channel_num];
            case (current_config_val)
                3'b000: current_state_idx = 0;
                3'b001: current_state_idx = 1;
                3'b011: current_state_idx = 2;
                3'b101: current_state_idx = 3;
                3'b111: current_state_idx = 4;
                default: current_state_idx = 0;
            endcase
            case (desired_config)
                3'b000: target_state_idx = 0;
                3'b001: target_state_idx = 1;
                3'b011: target_state_idx = 2;
                3'b101: target_state_idx = 3;
                3'b111: target_state_idx = 4;
                default: target_state_idx = 0;
            endcase
            if (target_state_idx >= current_state_idx)
                presses_needed = target_state_idx - current_state_idx;
            else
                presses_needed = (5 - current_state_idx) + target_state_idx;
            for (i = 0; i < presses_needed; i = i + 1) begin
                press_button(3'd2);
                #200;
            end
        end
    endtask

    // UART capture: direct internal observation of DUT's streamer
    integer uart_byte_count;
    reg [7:0] uart_rx_buffer [0:4095];

    // Simple monitor that samples DUT internal handshake at sys_clk
    // This avoids any async sampling/baud timing issues entirely.
    task automatic uart_monitor;
        begin
            uart_byte_count = 0;
            // wait until streamer becomes busy to start counting
            @(posedge sys_clk);
            wait (u_dut.u_uart_streamer.busy == 1'b1);
            // capture bytes while streamer is active; also allow trailing cycles
            while (u_dut.u_uart_streamer.busy || (uart_byte_count < 2054)) begin
                @(posedge sys_clk);
                if (u_dut.u_uart_streamer.tx_valid) begin
                    uart_rx_buffer[uart_byte_count] = u_dut.u_uart_streamer.tx_data;
                    uart_byte_count = uart_byte_count + 1;
                    if (uart_log)
                        $fwrite(uart_log, "%02h\n", u_dut.u_uart_streamer.tx_data);
                end
                if (uart_byte_count >= 4096) disable uart_monitor; // safety
            end
        end
    endtask

    // Run monitor concurrently
    initial begin : uart_monitor_thread
        uart_monitor();
    end

    // ---------------- Main Test Flow ----------------
    initial begin : main
        // reset & init
        sys_rst_n          = 1'b0;
        probe_signals      = 8'h00;  // Tied to 0 (using internal signals)
        btn_trigger_en     = 1'b1;
        btn_channel_select = 1'b1;
        btn_type_select    = 1'b1;
        btn_trigger_mode   = 1'b1;
        sw_test_enable     = tb_use_test_mode;
        sw_test_pattern    = tb_test_pattern;

        #100; sys_rst_n = 1'b1; #100;

        // configure CH0 = 101 (level-high) for quick trigger
        configure_channel(3'd0, 3'b101);
        print_config();

        // Using internal signals, no external probe stimulus needed
        $display("[TB] Observing internal signals (pattern=%0d)...", sw_test_pattern);

        // UART monitor already launched in parallel in initial block above
        $display("[TB] UART direct monitor launched (internal tx_valid/tx_data)...");

        // start capture
        press_button(3'd0); // run
        $display("[TB] Capture started, waiting for completion...");

        // wait until capture done
        wait (u_dut.capture_done == 1'b1);
        $display("[TB] capture_done=1, trigger_index=%0d", u_dut.trigger_index);

        // Wait for UART streamer to run and finish (robust vs. fixed delay)
        $display("[TB] Waiting for UART streamer busy...");
        wait (u_dut.u_uart_streamer.busy == 1'b1);
        $display("[TB] UART streamer busy=1 (transmitting) at t=%0t", $time);
        wait (u_dut.u_uart_streamer.busy == 1'b0);
        $display("[TB] UART streamer busy=0 (done) at t=%0t", $time);

        // Wait for expected payload (2054 bytes = 6 header + 2048 data)
        wait_ns = 0;
        while ((uart_byte_count < 2054) && (wait_ns < 500_000_000)) begin // 500 ms guard
            #1000; // 1 us
            wait_ns = wait_ns + 1000;
        end
        if (uart_byte_count >= 2054)
            $display("[TB] UART captured %0d bytes (>=2054)", uart_byte_count);
        else
            $display("[TB] ERROR: UART capture timeout after %0d ns, only %0d bytes", wait_ns, uart_byte_count);

        // Verify exact expected byte count
        if (uart_byte_count != 2054) begin
            $display("[TB] ERROR: Byte count mismatch. expected=2054 got=%0d", uart_byte_count);
        end

        // Parse and verify header: 0x55 0xAA LEN_L LEN_H TRIG_L TRIG_H
        if (uart_byte_count >= 6) begin
            frame_len_chk = {uart_rx_buffer[3], uart_rx_buffer[2]};
            trig_idx_chk  = {uart_rx_buffer[5], uart_rx_buffer[4]};
            if (uart_rx_buffer[0] != 8'h55 || uart_rx_buffer[1] != 8'hAA) begin
                $display("[TB] ERROR: Header sync invalid: %02h %02h",
                         uart_rx_buffer[0], uart_rx_buffer[1]);
            end else begin
                $display("[TB] Header OK: 55 AA LEN=%0d(0x%04h) TRIG=%0d",
                         frame_len_chk, frame_len_chk, trig_idx_chk);
            end
            if (frame_len_chk != 16'h0800) begin
                $display("[TB] ERROR: Frame Length mismatch. expected=2048 got=%0d(0x%04h)",
                         frame_len_chk, frame_len_chk);
            end else begin
                $display("[TB] Frame Length correct: 2048 bytes");
            end
        end else begin
            $display("[TB] ERROR: Fewer than 6 bytes captured, cannot parse header");
        end

        // stop
        press_button(3'd0);
        #1000;

        // finish
        if (uart_log) $fclose(uart_log);
        $display("[TB] Simulation finished.");
        $finish;
    end

endmodule
