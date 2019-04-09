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
// Mask and Compare
// -----------------------------------------------------------------------------
// Performs a mask and compare over a few pipeline stages. The input data is
// delayed to match the pipeline latency.
// -----------------------------------------------------------------------------
module mask_compare #(
  parameter DataBits = 32,
  parameter SyncBits = 1)
(
  input                     clk,
  input                     rst,
  //
  input                     din_valid,
  input [DataBits-1:0]      din_data,
  input [DataBits-1:0]      mask,
  input [DataBits-1:0]      value,
  input [SyncBits-1:0]      din_sync,
  //
  output reg                dout_valid,
  output reg [DataBits-1:0] dout_data,
  output reg                result,
  output reg [SyncBits-1:0] dout_sync
);

  // break up comparisons into 32-bit sets
  localparam CompSets = (DataBits + 31) / 32;

  reg                   mask_valid, comp_valid;
  reg [DataBits-1:0]    pipe_data[0:1];
  reg [SyncBits-1:0]    pipe_sync[0:1];
  reg [DataBits-1:0]    mask_result;
  reg [CompSets-1:0]    comp_result;

  // pad out to a multiple of 32 bits
  wire [CompSets*32-1:0] mask_result_pad = mask_result;
  wire [CompSets*32-1:0] value_pad       = value;

  integer i;
  always @(posedge clk) begin

    // defaults
    mask_valid <= 0;
    comp_valid <= 0;
    dout_valid <= 0;

    // Stage 1: apply mask
    if (din_valid) begin
      mask_valid   <= 1;
      pipe_data[0] <= din_data;
      pipe_sync[0] <= din_sync;
      mask_result  <= din_data & mask;
    end

    // Stage 2: compare in sets of 32-bits
    if (mask_valid) begin
      comp_valid <= 1;
      pipe_data[1] <= pipe_data[0];
      pipe_sync[1] <= pipe_sync[0];
      for (i=0; i < CompSets; i=i+1) begin
        comp_result[i] <= (mask_result_pad[32*i +: 32] == value_pad[32*i +: 32]);
      end
    end

    // Stage 3: and-reduce comparison results
    if (comp_valid) begin
      dout_valid <= 1;
      dout_data  <= pipe_data[1];
      dout_sync  <= pipe_sync[1];
      result     <= &comp_result;
    end

    if (rst) begin
      mask_valid <= 0;
      comp_valid <= 0;
      dout_valid <= 0;
    end
  end

endmodule
