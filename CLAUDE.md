# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Development Environment
- OS: Windows 10.0.26100
- Shell: Git Bash
- Path format: Windows (use forward slashes in Git Bash)
- File system: Case-insensitive
- Line endings: CRLF (configure Git autocrlf)

## Project Overview

This is an **FPGA-based Logic Analyzer** implemented in Verilog for Xilinx FPGAs (Vivado 2020.2). It captures 8-channel digital signals with configurable trigger conditions and exports data via UART.

**Key Features:**
- 8-channel sampling with 2048-sample ring buffer
- Per-channel trigger configuration (edge/level, rising/falling, enable/disable)
- Three trigger modes: OR, AND-accumulate (edge latch), AND-coincident (same-cycle)
- Ring buffer with configurable pre/post-trigger samples
- UART data export (115200 baud) with frame protocol
- Integrated ILA support for on-chip debugging
- Test signal generator for validation

## Project Structure

```
src/                      # RTL source files (Verilog modules)
├── fpga_top.v           # Top-level integration (buttons, ILA, UART)
├── logic_analyzer_core.v # Core FSM: sampling, triggering, ring buffer
├── sample_buffer.v      # Dual-port BRAM (2048x8)
├── uart_bram_streamer.v # Frame-based UART exporter
├── uart_tx.v            # UART transmitter (8N1)
├── input_synchronizer.v # Metastability protection (3-stage CDC)
├── debounce.v           # Button debouncing (simulation-aware)
└── test_signal_gen.v    # Internal test signal generator

sim/                      # Testbenches
├── tb_fpga_top_config.v # Full system test with configuration
└── tb_*.v               # Component-level testbenches

python/                   # Host-side tools
├── uart_single_frame_viewer.py # Receive and plot waveforms
└── analyze_trigger.py    # Trigger analysis tool

docs/                     # Documentation
├── UART_DEBUG_GUIDE.md   # ILA vs CH340 debugging
├── ILA_SETUP_GUIDE.md    # Vivado ILA configuration
├── ILA_QUICK_START.md
└── UPDATE_ILA_STEPS.md

logic_analyzer/           # Vivado project directory
└── logic_analyzer.xpr    # Vivado project file

scripts/                  # TCL automation scripts
├── update_ila_probes.tcl
└── increase_ila_depth.tcl
```

## Common Development Commands

### Simulation (ModelSim/Vivado Simulator)

**Run full system testbench:**
```tcl
# In Vivado TCL console
cd E:/fpga_class/vivado/logic_analyzer/logic_analyzer
launch_simulation
run all
```

Or directly with xsim:
```bash
cd logic_analyzer/logic_analyzer.sim/sim_1/behav/xsim
./tb_fpga_top_config.sh  # Linux/Git Bash
```

**Key simulation parameter:**
- The `debounce.v` module uses `SIMULATION` macro to reduce debounce delay from 20ms to ~10µs
- Testbenches define this macro to speed up simulation 100x

### Synthesis and Implementation

**Open Vivado project:**
```tcl
vivado logic_analyzer/logic_analyzer.xpr
```

**Command-line synthesis (if needed):**
```tcl
launch_runs synth_1
wait_on_run synth_1
launch_runs impl_1
wait_on_run impl_1
launch_runs impl_1 -to_step write_bitstream
```

**ILA configuration:**
- ILA is auto-instantiated in `fpga_top.v` (excluded during simulation via `ifndef SIMULATION`)
- 26 probes monitor: sample data, UART signals, configuration state, trigger status
- Probes 18-25 specifically for UART debugging

### Hardware Debugging

**Program FPGA:**
```tcl
open_hw_manager
connect_hw_server
open_hw_target
set_property PROGRAM.FILE {logic_analyzer.runs/impl_1/fpga_top.bit} [current_hw_device]
program_hw_devices
refresh_hw_device [current_hw_device]
```

**UART data capture (Python):**
```bash
cd python
python uart_single_frame_viewer.py  # Modify COM port in script
```

## Architecture Overview

### Data Flow

```
External Signals (probe_signals[7:0])
    ↓ [3-stage CDC: input_synchronizer]
Sample Data → logic_analyzer_core (FSM)
    ↓ [Ring buffer write]
BRAM (sample_buffer) ← 2048x8
    ↓ [On capture_done]
UART Export (uart_bram_streamer)
    ↓ [115200 baud, 8N1]
Host PC (Python viewer)
```

### State Machine (logic_analyzer_core.v)

```
IDLE → WAIT_TRIGGER → POST_CAPTURE → DONE
   ↑___________________________|
      (clear_done from UART completion)
```

**Ring buffer behavior:**
- Continuously writes during WAIT_TRIGGER (address wraps naturally)
- On trigger: records `trigger_index = wr_addr`
- Continues for `POST_TRIGGER_SAMPLES` (default: half buffer = 1024)
- Final buffer contains: PRE (older data) + trigger point + POST (newer data)

### Trigger Logic

**Per-channel 3-bit configuration** (trigger_config[ch][2:0]):
- bit[0]: Enable (1=active, 0=ignore)
- bit[2]: Mode (0=edge, 1=level)
- bit[1]: Polarity (edge: 0=rising/1=falling; level: 0=high/1=low)

**Three trigger modes** (trigger_mode[1:0]):
- `00`: **OR** - any enabled channel triggers
- `01`: **AND-accumulate** - all channels must trigger, edge events latched
- `10`: **AND-coincident** - all channels must trigger in same cycle

**Edge latch mechanism (AND-accumulate mode):**
- Edge events are "sticky" - once CH0 rising edge occurs, it's remembered
- Level triggers checked in real-time
- This allows asynchronous multi-channel edge triggering
- Latch cleared on: IDLE, config change, or trigger completion

### UART Frame Protocol

```
Frame structure (2054 bytes total):
┌────────┬────────┬─────────┬──────────────────┐
│ HEADER │  LEN   │  TRIG   │      DATA        │
│ 2 bytes│ 2 bytes│ 2 bytes │   2048 bytes     │
│0x55 0xAA│ 0x0008│  index  │   sample data    │
└────────┴────────┴─────────┴──────────────────┘
```

**Little-endian format:**
- LEN: `0x0008` = 2048 samples
- TRIG: trigger_index (e.g., `0x0001` = byte 1)

**Timing:** ~178ms per frame at 115200 baud

## Critical Design Details

### 1. Simulation vs Hardware

**debounce.v parameter:**
```verilog
// Hardware: 20ms @ 50MHz
parameter integer DEBOUNCE_CNT_MAX = 20'd999_999

// Override in testbench for fast simulation:
fpga_top #(.DEBOUNCE_CNT_MAX(20'd500)) dut (...);
```

**ILA exclusion:**
```verilog
`ifndef SIMULATION
    ila u_ila_la (...);  // Only synthesized, not simulated
`endif
```

### 2. Metastability Protection

**input_synchronizer.v:**
- 3-stage CDC for external async signals
- Upgraded from 2-stage for "critical reliability" (see comments)

### 3. Glitch Prevention

**fpga_top.v lines 109-143:**
- `trigger_enable_state` synchronized with extra register `trigger_enable_sync`
- Prevents glitches from button press racing with sampling clock

### 4. UART-LA Coordination

**Automatic restart mechanism:**
```verilog
// fpga_top.v line 298
assign clear_done_pulse = uart_done && !uart_done_d1;
```
- When UART finishes exporting, `clear_done` tells LA core to return to WAIT_TRIGGER
- Enables continuous capture mode

### 5. BRAM Read Latency

**uart_bram_streamer.v state machine:**
- `S_PREF` state prefetches first byte (accounts for 1-cycle sync read delay)
- `data_latched` register aligns timing

## Known Issues and Fixes

See [logic_analyzer/SIMULATION_FIXES.md](logic_analyzer/SIMULATION_FIXES.md) for detailed history:

1. **Debounce timing mismatch** - Fixed with simulation macro
2. **AND-mode edge triggering** - Fixed with edge_triggered_latch
3. **Config change race condition** - Fixed with trigger_config_changed signal
4. **Legacy mode detection bug** - Fixed by removing buggy fallback logic

## Pin Constraints

**Default constraint file:** `src/logic_analyzer.xdc`

**Key pins (adjust for your board):**
```tcl
set_property PACKAGE_PIN V18 [get_ports uart_tx]
set_property IOSTANDARD LVCMOS33 [get_ports uart_tx]

# External probes, buttons, test switches - see .xdc for full list
```

## Python Host Software

**Dependencies:**
```bash
pip install pyserial matplotlib numpy
```

**Usage:**
```python
# Modify COM port in uart_single_frame_viewer.py:
SERIAL_PORT = 'COM11'  # Windows
# or '/dev/ttyUSB0'    # Linux

python python/uart_single_frame_viewer.py
```

**Expected output:** 8-channel waveform plot with trigger marker

## Debugging Strategy

1. **Simulation first** - Use `tb_fpga_top_config.v` to verify logic
2. **ILA for internal signals** - Monitor state machine, trigger conditions
3. **CH340 for end-to-end** - Validate actual UART communication

**ILA probe recommendations:**
- Trigger on `probe3 (busy)` rising edge to capture UART start
- Check `probe0 (tx_data)` first 6 bytes: `55 AA 00 08 XX XX`
- Monitor `probe22 (rd_addr)` for BRAM read progress (0→2047)

## Important Implementation Notes

### When modifying trigger logic:
- Always consider both edge and level modes
- Update `edge_triggered_latch` management in all FSM states
- Test with `tb_fpga_top_config.v` scenarios (OR mode test 1, AND mode test 2)

### When changing buffer size:
- Update `ADDR_WIDTH` parameter in `fpga_top.v`
- Regenerate BRAM IP if using Xilinx IP Catalog
- Adjust `POST_TRIGGER_SAMPLES` parameter if needed

### When modifying UART protocol:
- Update Python parser (`uart_single_frame_viewer.py` line 18 FRAME_HEADER)
- Adjust `uart_bram_streamer.v` state machine header bytes
- Document in UART_DEBUG_GUIDE.md

### ILA probe management:
- Use scripts in `scripts/` for batch updates
- `update_ila_probes.tcl` - Refresh probe connections
- `increase_ila_depth.tcl` - Expand sample depth

## Test Signal Generator

**test_signal_gen.v patterns:**
- `2'b00`: Counter pattern (increments each cycle)
- `2'b01`: Internal bus 0 (capture_done, triggered, capturing, uart_busy, wr_addr[3:0])
- `2'b10`: Internal bus 1 (trigger_mode, channel_idx, button pulses)

**Usage in testbench:**
```verilog
sw_test_enable = 1;      // Use internal signals
sw_test_pattern = 2'b00; // Select counter mode
```

## Vivado Project Path

**Project file:** `E:\fpga_class\vivado\logic_analyzer\logic_analyzer\logic_analyzer.xpr`

**Important subdirectories:**
- `.gen/sources_1/ip/ila/` - Generated ILA IP
- `.runs/impl_1/` - Implementation outputs (bitstream)
- `.hw/hw_1/wave/` - ILA captured waveforms
- `.cache/` - IP cache (commit only checksums, not full IP)

## Version Control Notes

**Committed files:**
- All `src/*.v` RTL sources
- All `sim/tb_*.v` testbenches
- `python/*.py` host tools
- `docs/*.md` documentation
- `logic_analyzer.xdc` constraints

**Ignored (.gitignore recommended):**
- `logic_analyzer/.Xil/` - Temporary Vivado files
- `logic_analyzer/.runs/` - Build outputs
- `logic_analyzer/.cache/ip/` - Large IP cache files
- `*.jou`, `*.log` - Vivado log files
- `vivado_pid*.str` - Lock files

## Key Parameters Reference

| Parameter | Default | Location | Purpose |
|-----------|---------|----------|---------|
| DATA_WIDTH | 8 | logic_analyzer_core.v | Channels per sample |
| ADDR_WIDTH | 11 | logic_analyzer_core.v | Buffer depth (2^11=2048) |
| POST_TRIGGER_SAMPLES | 1024 | logic_analyzer_core.v | Post-trigger capture size |
| CLK_FREQ | 50000000 | fpga_top.v | System clock (50MHz) |
| BAUD_RATE | 115200 | uart_bram_streamer.v | UART speed |
| DEBOUNCE_CNT_MAX | 999999 | fpga_top.v | Button debounce (~20ms) |
| SYNC_STAGES | 3 | input_synchronizer.v | CDC flip-flop chain |

## Troubleshooting Quick Reference

**Symptom: Simulation hangs in WAIT_TRIGGER**
→ Check `DEBOUNCE_CNT_MAX` override in testbench instantiation

**Symptom: AND mode never triggers**
→ Verify `edge_triggered_latch` is being set, not cleared by config_changed

**Symptom: UART receives wrong data**
→ Use ILA probe18 (tx_data) to verify internal correctness first

**Symptom: trigger_index doesn't match expected position**
→ Remember ring buffer wraps; use modulo FRAME_SIZE in Python

**Symptom: ILA not visible in Hardware Manager**
→ Check `.ltx` probe file loaded; verify ILA instantiation not ifdef'd out

## Codex CLI Integration

This project has Codex CLI (ZenMCP) configured for advanced AI assistance. Available commands:

```bash
codex exec "请全面检查项目中的所有 Verilog 代码"
codex exec "分析 src/ 目录下的代码，列出前5个最重要的问题"
```

Configured CLI clients: claude, codex, gemini


## 使用准则概览

- 回复语言必须使用简体中文。
- 接到需求后先整理详细的to-do列表，发送用户确认;若用户提出修改意见，需重新整理并确认。
-执行to-do 时，每完成一项都要暂停并请用户确认后再继续下一项。
- 涉及代码或文档改动时，使用Approve 流程，请用户确认后再提交最终变更。
- 开发过程中若有任何不确定之处，必须主动向用户提问。
