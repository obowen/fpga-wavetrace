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
// ----------------------------------------------------------------------------
// Stream Synchronous (1-clock) Fifo
// ----------------------------------------------------------------------------
// A stream wrapper around a Synchronous 1-clock FIFO.
//
// ----------------------------------------------------------------------------
module stream_fifo_1clk (clk, rst, din_valid, din_ready, din_data,
                         dout_valid, dout_ready, dout_data, used);
`include "util.vh"
  parameter                   Width = 8;
  parameter                   Depth = 128; // non-power of 2 is supported
  // --------------------------------------------------------------------------
  input                       clk;
  input                       rst;
  //
  input                       din_valid;
  output                      din_ready;
  input [Width-1:0]           din_data;
  //
  output                      dout_valid;
  input                       dout_ready;
  output [Width-1:0]          dout_data;
  //
  output [clog2(Depth+1)-1:0] used;
  // --------------------------------------------------------------------------

  wire full, empty, rd_en, wr_en;

  assign wr_en     = ~full & din_valid;
  assign din_ready = ~full;

  assign rd_en      = ~empty & dout_ready;
  assign dout_valid = ~empty;

  fifo_1clk #(
    .Width (Width),
    .Depth (Depth))
  fifo(
    .clk     (clk),
    .rst     (rst),
    .wr_en   (wr_en),
    .wr_data (din_data),
    .full    (full),
    .rd_en   (rd_en),
    .rd_data (dout_data),
    .empty   (empty),
    .used    (used));

endmodule


