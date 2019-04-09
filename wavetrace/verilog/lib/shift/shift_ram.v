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
// Shift_ram
// -----------------------------------------------------------------------------
// A multi-bit shift register using a simple dual port RAM.
//
// -----------------------------------------------------------------------------
module shift_ram #(
  parameter Width = 8,
  parameter Depth = 32)
(
  input              clk,
  input              rst,
  input [Width-1:0]  din_data,
  input              en,
  output [Width-1:0] dout_data
);

`include "util.vh"

  reg  [clog2(Depth)-1:0] wr_addr;
  wire [clog2(Depth)-1:0] wr_addr_next, rd_addr;

  assign wr_addr_next = (wr_addr == Depth-1) ? 0 : wr_addr + 1;

  always @(posedge clk) begin
    if (en) begin
      wr_addr <= wr_addr_next;
    end
    if (rst) begin
      wr_addr <= 0;
    end
  end

  assign rd_addr = (en) ? wr_addr_next : wr_addr;

  ram_1c_1r_1w #(
    .Width (Width),
    .Depth (Depth))
  ram (
    .clk     (clk),
    .wr_en   (en),
    .wr_addr (wr_addr),
    .wr_data (din_data),
    .rd_addr (rd_addr),
    .rd_data (dout_data));

endmodule
