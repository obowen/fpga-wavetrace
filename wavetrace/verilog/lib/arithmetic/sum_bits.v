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
// Sum Bits
// -----------------------------------------------------------------------------
// Counts the number of ones in a vector using multiple pipeline stages
//
// NOTE: latency through this block is: 1 + clog2(InBits) - 2
//
// -----------------------------------------------------------------------------
module sum_bits (clk, en, bits, sum);
`include "util.vh"
  parameter  InBits  = 32;  // Must be multiple of 4!
  //
  localparam OutBits = clog2(InBits + 1);
  // ---------------------------------------------------------------------------
  input               clk;
  input               en;
  //
  input [InBits-1:0]  bits;
  //
  output[OutBits-1:0] sum;
  // ---------------------------------------------------------------------------

  // count ones in 4-bit vector using LUT.
  function automatic [2:0] sum_bits_4(input [3:0] x);
    reg [2:0] r;
    begin
      case (x)
        4'b0000: r=0;
        4'b0001: r=1;
        4'b0010: r=1;
        4'b0011: r=2;
        4'b0100: r=1;
        4'b0101: r=2;
        4'b0110: r=2;
        4'b0111: r=3;
        4'b1000: r=1;
        4'b1001: r=2;
        4'b1010: r=2;
        4'b1011: r=3;
        4'b1100: r=2;
        4'b1101: r=3;
        4'b1110: r=3;
        4'b1111: r=4;
      endcase
      sum_bits_4 = r;
    end
  endfunction

  localparam AdderStages = clog2(InBits) - 2;

  // First stage: use a LUT for every 4 bits
  reg [3*InBits/4-1:0] lut_sum;
  integer              i;
  always @(posedge clk) begin
    if (en) begin
      for (i=0; i < InBits/4; i=i+1) begin
        lut_sum[3*i +: 3] <= sum_bits_4(bits[i*4 +: 4]);
      end
    end
  end

  // Remaining stages: use binary adder tree
  generate
    if (AdderStages < 1) begin: no_tree
      assign sum = lut_sum;
    end else begin: use_tree
      adder_tree #(
        .DataBits (3),
        .NumWords (InBits/4))
      add_tree (
        .clk       (clk),
        .en        (en),
        .din_data  (lut_sum),
        .dout_data (sum));
    end
  endgenerate

endmodule
