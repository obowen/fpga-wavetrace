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
// Stream Asynchronous (2-clock) Fifo
// ----------------------------------------------------------------------------
// A stream wrapper around an asynchronous 2-clock FIFO.
//
// ----------------------------------------------------------------------------
module stream_fifo_2clk (din_clk,  din_rst,  din_valid,  din_ready,  din_data,  din_free,
                         dout_clk, dout_rst, dout_valid, dout_ready, dout_data, dout_used);
`include "util.vh"
  parameter             Width = 8;
  parameter             Depth = 1024; // *must* be power of 2!
  localparam            UsedBits  = clog2(Depth+1);
  // ---------------------------------------------------------------
  input                 din_clk;
  input                 din_rst;
  input                 din_valid;
  output                din_ready;
  input  [Width-1:0]    din_data;
  output [UsedBits-1:0] din_free;
  //
  input                 dout_clk;
  input                 dout_rst;
  output                dout_valid;
  input                 dout_ready;
  output [Width-1:0]    dout_data;
  output [UsedBits-1:0] dout_used;
  // --------------------------------------------------------------

  wire full, empty, rd_en, wr_en;

  assign wr_en     = ~full & din_valid;
  assign din_ready = ~full;

  assign rd_en      = ~empty & dout_ready;
  assign dout_valid = ~empty;

  fifo_2clk #(
    .Width (Width),
    .Depth (Depth))
  fifo(
    .wr_clk  (din_clk),
    .wr_rst  (din_rst),
    .wr_en   (wr_en),
    .wr_data (din_data),
    .wr_free (din_free),
    .wr_full (full),
    //
    .rd_clk  (dout_clk),
    .rd_rst  (dout_rst),
    .rd_en   (rd_en),
    .rd_data (dout_data),
    .rd_used (dout_used),
    .rd_empty(empty));

endmodule


