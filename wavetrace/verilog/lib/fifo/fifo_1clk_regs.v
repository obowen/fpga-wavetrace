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
// ----------------------------------------------------------------------------------
// Synchronous Fifo, Implemented using Registers
// ----------------------------------------------------------------------------------
// Implemented using an array of registers and muxes.
//
// NOTE: There is no underflow or overflow checking!
//
// ----------------------------------------------------------------------------------
module fifo_1clk_regs (clk, rst, wr_en, wr_data, full, rd_en, rd_data, empty, used);
`include "util.vh"
  parameter                 Width    = 8;
  parameter                 Depth    = 4;
  //
  localparam                UsedBits = clog2(Depth+1);
  // ---------------------------------------------------------------
  input                     clk;
  input                     rst;
  //
  input                     wr_en;
  input [Width-1:0]         wr_data;
  output                    full;
  //
  input                     rd_en;
  output [Width-1:0]        rd_data;
  output                    empty;
  //
  output reg [UsedBits-1:0] used;
  // ---------------------------------------------------------------

  reg [Depth*Width-1:0] data;


  always @(posedge clk) begin:fifo_regs
    reg [UsedBits-1:0] used_i;
    integer            i;

    used_i = used;

    // shift out data
    if (rd_en) begin
      data   <= data >> Width;
      used_i  = used_i - 1;
    end

    // load new data into current slot
    if (wr_en) begin
      for (i=0; i < Depth; i=i+1) begin
        if (i == used_i)
          data[i*Width +: Width] <= wr_data;
      end
      used_i = used_i + 1;
    end

    used <= used_i;

    if (rst) begin
      used <= 0;
    end
  end

  assign rd_data  = data[Width-1:0];
  assign full     = (used == Depth);
  assign empty    = (used == 0);

endmodule

