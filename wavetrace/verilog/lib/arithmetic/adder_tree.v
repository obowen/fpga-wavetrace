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
// Adder Tree (Binary)
// -----------------------------------------------------------------------------
// A generic binary adder tree.
//
// -----------------------------------------------------------------------------
module adder_tree (clk, en, din_data, dout_data);
`include "util.vh"
  parameter  DataBits = 8;
  parameter  NumWords = 4;  // Must be power of 2!
  //
  localparam Stages   = clog2(NumWords);
  localparam SumBits  = DataBits + Stages;
  // ---------------------------------------------------------------------------
  input                          clk;
  input                          en;
  //
  input  [DataBits*NumWords-1:0] din_data;
  //
  output reg [SumBits-1:0]       dout_data;
  // ---------------------------------------------------------------------------

  localparam HalfBits = DataBits * NumWords / 2;
  localparam TreeBits = (NumWords == 2) ? DataBits :
                                          (DataBits + clog2(NumWords/2));

  wire [HalfBits-1:0]  din_data_0,  din_data_1;
  wire [TreeBits-1:0]  tree_data_0, tree_data_1;

  // split the input vector in half
  assign {din_data_1, din_data_0} = din_data;

  generate if (NumWords > 2) begin: add_trees
    // recursively instantiate two smaller adder trees
    adder_tree #(
      .DataBits (DataBits),
      .NumWords (NumWords/2))
    tree_0 (
      .clk      (clk),
      .en       (en),
      .din_data (din_data_0),
      .dout_data(tree_data_0));

    adder_tree #(
      .DataBits (DataBits),
      .NumWords (NumWords/2))
    tree_1 (
      .clk      (clk),
      .en       (en),
      .din_data (din_data_1),
      .dout_data(tree_data_1));

  end else begin: no_trees
    assign tree_data_0 = din_data_0;
    assign tree_data_1 = din_data_1;
  end endgenerate

  // final addition and output register
  always @(posedge clk) begin
    if (en)
      dout_data <= tree_data_0 + tree_data_1;
  end

endmodule
