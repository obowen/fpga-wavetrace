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
// RAM 2-clocks, 1 Read port, 1 Write Port
// -----------------------------------------------------------------------------
// A platform independant inferred simple dual port Block RAM with separate
// read and write clocks.
//
// Implementation based on Doulous Tech Note:
// "HDL Synthesis Inference of FPGA Memories"
//
// NOTE:
// To maximize compatability across different platforms, we do not rely on any
// specific handling of read / write collisions between the two ports as the
// value of the read data can be nondeterministic. If this occurs during
// simulation, an assertion will fail, and read-data is replaced with X's.
//
// -----------------------------------------------------------------------------
module ram_2c_1r_1w (wr_clk, wr_en, wr_addr, wr_data, rd_clk, rd_addr, rd_data);
`include "util.vh"
  //
  parameter  Width = 18;
  parameter  Depth = 64;
  parameter  ReportCollision = 1;
  //
  localparam AddrBits = clog2(Depth);
  //
  input                  wr_clk;
  input                  wr_en;
  input [AddrBits-1:0]   wr_addr;
  input [Width-1:0]      wr_data;
  //
  input                  rd_clk;
  input [AddrBits-1:0]   rd_addr;
  output reg [Width-1:0] rd_data;
  // -------------------------------------------------------------------------------

  // ------------
  // Memory Model
  // ------------
  reg [Width-1:0] mem[0:Depth-1];

  always_ff @(posedge wr_clk) begin
    if (wr_en)
      mem[wr_addr] <= wr_data;
  end

  reg [Width-1:0] rd_data_i;
  always_ff @(posedge rd_clk) begin
    rd_data_i <= mem[rd_addr];
  end

  // ----------------------------------
  // Collision Detection for Simulation
  // ----------------------------------
  // synthesis translate_off
  reg collision;
  always_ff @(posedge rd_clk) begin
    collision <= wr_en && wr_addr == rd_addr;
    if (ReportCollision) begin
      assert (!wr_en || (wr_addr != rd_addr)) else
        $error("Read and write to same address: read data indeterminate");
    end
  end
  // synthesis translate_on

  always_comb begin
    rd_data = rd_data_i;
    // synthesis translate_off
    if (collision)
      rd_data = {{Width}{1'bx}};
    // synthesis translate_on
  end

endmodule
