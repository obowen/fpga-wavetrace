// Copyright 2019 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.
//
// ------------------------------------------------------------------
// Wave Trace
// ------------------------------------------------------------------
// An onchip debugger / logic analyzer
// ------------------------------------------------------------------
module wavetrace #(
  parameter DataBits     = 32,
  parameter PreTrigDepth = 64,
  parameter CaptDepth    = 512,
  parameter ClockHz      = 80000000,
  parameter UartBaud     = 115200)
(
  input                clk,
  input                rst,
  //
  input                uart_rx,
  output               uart_tx,
  //
  input [DataBits-1:0] din_data
);
`include "util.vh"

  // ----
  // Uart
  // ----
  wire       tx8_valid, tx8_ready, rx8_valid, rx8_ready;
  wire [7:0] tx8_data, rx8_data;

  uart #(
    .ClockHz(ClockHz),
    .Baud   (UartBaud))
  uart(
    .clk        (clk),
    .rst        (rst),
    //
    .uart_rx    (uart_rx),
    .uart_tx    (uart_tx),
    //
    .din_valid  (tx8_valid),
    .din_ready  (tx8_ready),
    .din_data   (tx8_data),
    //
    .dout_valid (rx8_valid),
    .dout_data  (rx8_data),
    .dout_ready (rx8_ready));

  // --------------------------------------
  // Serialize / Deserialize 8-bit : 32-bit
  // --------------------------------------
  wire        tx32_valid, tx32_ready, rx32_valid, rx32_ready;
  wire [31:0] tx32_data, rx32_data;

  stream_deserializer #(
    .Ratio    (4),
    .DataBits (8))
  dser(
    .clk       (clk),
    .rst       (rst),
    //
    .in_valid  (rx8_valid),
    .in_ready  (rx8_ready ),
    .in_data   (rx8_data),
    //
    .out_valid (rx32_valid),
    .out_ready (rx32_ready),
    .out_data  (rx32_data));

  stream_serializer #(
    .Ratio    (4),
    .DataBits (8))
  ser(
    .clk       (clk),
    .rst       (rst),
    //
    .in_valid  (tx32_valid),
    .in_ready  (tx32_ready),
    .in_data   (tx32_data),
    //
    .out_valid (tx8_valid),
    .out_ready (tx8_ready),
    .out_data  (tx8_data));

  // ----------------------
  // APB Instruction Master
  // ----------------------
  wire        mst_psel, mst_penable, mst_pwrite, mst_pready, mst_pslverr;
  wire [31:0] mst_paddr, mst_pwdata, mst_prdata;

  apb_master apb (
    .clk        (clk),
    .rst        (rst),
    //
    .din_valid  (rx32_valid),
    .din_ready  (rx32_ready),
    .din_data   (rx32_data),
    //
    .dout_valid (tx32_valid),
    .dout_ready (tx32_ready),
    .dout_data  (tx32_data),
    //
    .mst_paddr  (mst_paddr),
    .mst_pwrite (mst_pwrite),
    .mst_pwdata (mst_pwdata),
    .mst_psel   (mst_psel),
    .mst_penable(mst_penable),
    .mst_pready (mst_pready),
    .mst_prdata (mst_prdata),
    .mst_pslverr(mst_pslverr));

  // ------------
  // Wave Capture
  // ------------
  wave_capture #(
    .DataBits     (DataBits),
    .PreTrigDepth (PreTrigDepth),
    .CaptDepth    (CaptDepth),
    .ClockHz      (ClockHz))
  capt(
    .clk        (clk),
    .rst        (rst),
    //
    .din_data   (din_data),
    //
    .cfg_paddr  (mst_paddr[31:0]),
    .cfg_pwrite (mst_pwrite),
    .cfg_pwdata (mst_pwdata),
    .cfg_psel   (mst_psel),
    .cfg_penable(mst_penable),
    .cfg_pready (mst_pready),
    .cfg_prdata (mst_prdata),
    .cfg_pslverr(mst_pslverr));

endmodule
