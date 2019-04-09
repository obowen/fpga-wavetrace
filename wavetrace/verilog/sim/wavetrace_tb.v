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
`timescale 1ns/100ps
`default_nettype none

module wavetrace_tb;

`include "util.vh"

  localparam CaptDepth = 512;
  localparam DataBits = 32'd72;
  localparam TrigRegs = (DataBits + 31) / 32;
  localparam NumBanks = (DataBits + 31) / 32;
  localparam BankAddrBits = clog2(NumBanks);
  localparam CaptMemAddr = CaptDepth << BankAddrBits;
  
  // ---------------
  // Clock and Reset
  // ---------------
  wire clk, rst;
  clock_gen clkgen(
    .clk (clk),
    .rst (rst));

  // --------
  // Commands
  // --------
  reg [31:0] inst_data;
  reg        inst_valid;
  wire       inst_ready;

  task do_write(input [31:0] addr, input [31:0] data); begin
    @(posedge clk);
    inst_data  = 32'hABCD0001;
    inst_valid = 1'b1;

    @(posedge clk);
    while (!inst_ready)
      @(posedge clk);

    inst_data = addr;

    @(posedge clk);
    while (!inst_ready)
      @(posedge clk);

    inst_data = data;

    @(posedge clk);
    while (!inst_ready)
      @(posedge clk);

    inst_valid = 1'b0;

  end endtask

  task do_read(input [31:0] addr); begin
    @(posedge clk);
    inst_data = 32'hABCD0002;
    inst_valid = 1'b1;

    @(posedge clk);
    while (!inst_ready)
      @(posedge clk);
    inst_data = addr;

    @(posedge clk);
    while (!inst_ready)
      @(posedge clk);
    inst_valid = 1'b0;
    // TODO: wait for read data?
  end endtask

  reg [31:0] count;

  initial begin
    inst_valid  = 0;
    inst_data   = 0;
    count       = 0;
    wait(!rst);
    @(posedge clk);

    do_write(5 << 2, 1);   // trigger mode
    do_write(16               << 2, 128); // trigger mask1
    do_write((16 +   TrigRegs) << 2, 128); // trigger mask2
    do_write((16 + 2*TrigRegs) << 2, 0);   // trigger val1
    do_write((16 + 3*TrigRegs) << 2, 128);   // trigger val2

//    do_write((16 + 4*TrigRegs) << 2, 2); // storage qualifier mask1
//    do_write((16 + 5*TrigRegs) << 2, 2); // storage qualifier mask2

    do_read (16 << 2);      // read mask back
    do_write(8 << 2, 2);   // sub-sample
    do_write(9 << 2, 1);   // go

    while (count < 8000) begin
      @(posedge clk);
      count <= count + 1;
    end

    do_read((CaptMemAddr)     << 2); // read capture buffer
    do_read((CaptMemAddr + 1) << 2); // read capture buffer
    do_read((CaptMemAddr + 2) << 2); // read capture buffer

    do_read((CaptMemAddr + 511) << 2); // read capture buffer
    do_read((CaptMemAddr + 512) << 2); // read capture buffer
    do_read((CaptMemAddr + 513) << 2); // read capture buffer

    do_read((CaptMemAddr + 1023) << 2); // read capture buffer
    do_read((CaptMemAddr + 1024) << 2); // read capture buffer
    do_read((CaptMemAddr + 1025) << 2); // read capture buffer


  end

  wire [7:0]  inst8_data;
  wire        inst8_valid, inst8_ready;
  stream_serializer #(
    .Ratio    (4),
    .DataBits (8))
  ser(
    .clk       (clk),
    .rst       (rst),
    //
    .in_valid  (inst_valid),
    .in_ready  (inst_ready),
    .in_data   (inst_data),
    //
    .out_valid (inst8_valid),
    .out_ready (inst8_ready),
    .out_data  (inst8_data));


  // ---------
  // Host Uart
  // ---------
  wire       host_uart_tx, host_uart_rx;
  wire       rx_valid, rx_ready;
  wire [7:0] rx_data;

  uart #(
    .ClockHz (1000000),
    .Baud    ( 115200))
  uart(
    .clk        (clk),
    .rst        (rst),
    //
    .uart_rx    (host_uart_rx),
    .uart_tx    (host_uart_tx),
    //
    .din_valid  (inst8_valid),
    .din_ready  (inst8_ready),
    .din_data   (inst8_data),
    //
    .dout_valid (rx_valid),
    .dout_data  (rx_data),
    .dout_ready (rx_ready));


  ////////////////// TEMP ///////////////
  wire temp_uart_rx = host_uart_tx;
  wire temp_uart_tx;
  wire temp_valid, temp_ready;
  wire [7:0] temp_data;
  uart #(
    .ClockHz (1000000),
    .Baud    ( 115200))
  uart_TEMP(
    .clk        (clk),
    .rst        (rst),
    //
    .uart_rx    (temp_uart_rx),
    .uart_tx    (temp_uart_tx),
    //
    .din_valid  (temp_valid),
    .din_ready  (temp_ready),
    .din_data   (temp_data),
    //
    .dout_valid (temp_valid),
    .dout_data  (temp_data),
    .dout_ready (temp_ready));
  ////////////////


  // -------------
  // Stream Source
  // -------------
  wire       din_valid, din_ready;
  wire [31:0] din_data;

  stream_source #(
    .FILENAME    ("in.dat"),
    .NUM_SYMBOLS (1),
    //.SYMBOL_BITS ({DataBits}),
    .SYMBOL_BITS ({32'd32}),
    .THROUGHPUT  (100))
  src (
    .clk       (clk),
    .rst       (rst),
    .dout_ready(din_ready),
    .dout_valid(din_valid),
    .dout_data (din_data)
    );

  // delay the input data for the uart config to happen
  reg [31:0] delay_count;
  reg        din_active;
  always @(posedge clk) begin

    if (delay_count < 5000)
      delay_count <= delay_count + 1;
    else
      din_active  <= 1;

    if (rst) begin
      din_active <= 0;
      delay_count <= 0;
    end
  end

  assign din_ready = (din_active) ? 1 : 0;

  wire [DataBits-1:0] din_data_wt = {3{din_data}};
  wavetrace #(
    .DataBits (DataBits),
    .CaptDepth(CaptDepth),
    .ClockHz  (1000000),
    .UartBaud ( 115200))
  dut (
    .clk     (clk),
    .rst     (rst),
    .uart_rx (host_uart_tx),
    .uart_tx (host_uart_rx),
    .din_data(din_data_wt)
    );

endmodule
