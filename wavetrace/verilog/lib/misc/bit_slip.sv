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
// -----------------------------------------------------------------------------
// Bit Slipping Module
// -----------------------------------------------------------------------------
// This module implements a barrel-shifter to shift the position of the word
// boundaries in the incoming stream by some number of bits. A parameter
// specifies if incoming words are in little endian (i.e. LSB first) or big-
// endian format.
//
// -----------------------------------------------------------------------------
module bit_slip #(
  parameter  DataBits     = 32,
  parameter  MaxSlip      = 7,
  parameter  LittleEndian = 1)
(
  input                         clk,
  input                         rst,
  //
  input                         din_valid,
  output                        din_ready,
  input [DataBits-1:0]          din_data,
  //
  output                        dout_valid,
  input                         dout_ready,
  output [DataBits-1:0]         dout_data,
  //
  input [$clog2(MaxSlip+1)-1:0] slip_amount
);

  localparam MaxSlipBits = $clog2(MaxSlip + 1);
  localparam WinBits = DataBits + MaxSlip;

  logic [WinBits-1:0]  data_window;
  logic [DataBits-1:0] slip_data;
  logic [MaxSlip-1:0]  data_reg_n;
  logic [MaxSlip-1:0]  data_reg;

  // Select a slice from the data window with the specified slip amount
  generate if (LittleEndian) begin: little
    assign data_window = {din_data, data_reg};
    assign slip_data   = data_window[WinBits-1-slip_amount -: DataBits];
    assign data_reg_n  = din_data[DataBits-1 -: MaxSlip];
  end else begin: big
    assign data_window = {data_reg, din_data};
    assign slip_data   = data_window[slip_amount +: DataBits];
    assign data_reg_n  = din_data[0 +: MaxSlip];
  end endgenerate;

  // Buffer up enough bits for the max slip distance
  always_ff @(posedge clk) begin
    if (din_valid & din_ready) begin
      data_reg <= data_reg_n;
    end
  end

  // Buffer to register output
  stream_buf_v #(
    .DataBits(DataBits))
  obuf (
    .clk      (clk),
    .rst      (rst),
    .in_valid (din_valid),
    .in_ready (din_ready),
    .in_data  (slip_data),
    .out_valid(dout_valid),
    .out_ready(dout_ready),
    .out_data (dout_data));

endmodule
