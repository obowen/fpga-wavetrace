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
// LFSR Shifter
// -----------------------------------------------------------------------------
// An LFSR shift register that can be shifted by a parameterizable data-width
// each cycle.
//
// This module computes the next N bits of a 15-bit maximal length LFSR shift
// register, outputs the resulting vector, and shifts the LFSR regsiter by
// N positions.
//
// An initial seed can be provided by a parameter and changed during run-time
// via an input port.
//
// -----------------------------------------------------------------------------
module lfsr15_shift #(
  parameter DataBits = 32,
  parameter LfsrSeed = 15'h5555)
(
  input                 clk,
  input                 rst,
  //
  input [14:0]          seed,   // seed applied when 'init' is high
  input                 init,
  input                 shift,  // shifts LFSR data by DataBits when high
  output [DataBits-1:0] lfsr_data);

  // This uses a 15-bit maximal length LFSR polynomial
  localparam LfsrBits = 15;

  reg  [LfsrBits-1:0]            lfsr_reg;
  wire [LfsrBits + DataBits-1:0] lfsr_next;

  // Compute the next N lfsr bits
  assign lfsr_next[LfsrBits-1:0] = lfsr_reg;
  genvar i;
  generate
    for (i=LfsrBits; i < LfsrBits + DataBits; i=i+1) begin: lfsr_bits
      assign lfsr_next[i] = lfsr_next[i-15] ^ lfsr_next[i-14];
    end
  endgenerate

  // LFSR register
  always @(posedge clk) begin
    if (init) begin
      lfsr_reg <= seed;
    end else if (shift) begin
      lfsr_reg <= lfsr_next[DataBits + LfsrBits - 1 : DataBits];
    end
    if (rst) begin
      lfsr_reg <= LfsrSeed;
    end
  end

  assign lfsr_data = lfsr_next[DataBits-1:0];

endmodule
