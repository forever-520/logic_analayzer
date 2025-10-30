// Copyright 1986-2020 Xilinx, Inc. All Rights Reserved.
// --------------------------------------------------------------------------------
// Tool Version: Vivado v.2020.2 (win64) Build 3064766 Wed Nov 18 09:12:45 MST 2020
// Date        : Thu Oct 30 18:53:42 2025
// Host        : forever running 64-bit major release  (build 9200)
// Command     : write_verilog -force -mode synth_stub
//               e:/fpga_class/vivado/logic_analyzer/logic_analyzer/logic_analyzer.gen/sources_1/ip/ila/ila_stub.v
// Design      : ila
// Purpose     : Stub declaration of top-level module interface
// Device      : xc7z010clg400-2
// --------------------------------------------------------------------------------

// This empty module with port declaration file causes synthesis tools to infer a black box for IP.
// The synthesis directives are for Synopsys Synplify support to prevent IO buffer insertion.
// Please paste the declaration into a Verilog source file or add the file as an additional source.
(* X_CORE_INFO = "ila,Vivado 2020.2" *)
module ila(clk, probe0, probe1, probe2, probe3, probe4, probe5, 
  probe6, probe7, probe8, probe9, probe10, probe11, probe12, probe13, probe14, probe15, probe16, probe17)
/* synthesis syn_black_box black_box_pad_pin="clk,probe0[7:0],probe1[0:0],probe2[10:0],probe3[7:0],probe4[0:0],probe5[0:0],probe6[0:0],probe7[10:0],probe8[0:0],probe9[1:0],probe10[2:0],probe11[0:0],probe12[0:0],probe13[0:0],probe14[0:0],probe15[7:0],probe16[0:0],probe17[1:0]" */;
  input clk;
  input [7:0]probe0;
  input [0:0]probe1;
  input [10:0]probe2;
  input [7:0]probe3;
  input [0:0]probe4;
  input [0:0]probe5;
  input [0:0]probe6;
  input [10:0]probe7;
  input [0:0]probe8;
  input [1:0]probe9;
  input [2:0]probe10;
  input [0:0]probe11;
  input [0:0]probe12;
  input [0:0]probe13;
  input [0:0]probe14;
  input [7:0]probe15;
  input [0:0]probe16;
  input [1:0]probe17;
endmodule
