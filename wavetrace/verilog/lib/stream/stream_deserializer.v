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
// Stream Deserializer
// -----------------------------------------------------------------------------
// Converts a serial stream of valid data elements into a parallel bus output on
// a single valid cycle.
//
// NOTE: Data ordering is Little Endian (1st element received is output in
//       LSB position)
//
// -----------------------------------------------------------------------------
module stream_deserializer #(
  parameter DataBits = 8,
  parameter Ratio    = 2)
(
  input                       clk,
  input                       rst,
  //
  input                       in_valid,
  output                      in_ready,
  input [DataBits-1:0]        in_data,
  //
  output                      out_valid,
  input                       out_ready,
  output [Ratio*DataBits-1:0] out_data
);


  reg [(Ratio-1)*DataBits-1:0] data_r;
  reg [Ratio-1:0]              count;
  wire                         last = count[Ratio-1];
  integer                      i;

  always @(posedge clk) begin

    // one hot counter to track deserialization state
    if (in_valid & in_ready) begin
      count <= last ? 1 : count << 1;
    end

    // load data based on bit in one-hot counter
    for (i=0; i < Ratio-1; i=i+1) begin
      if (count[i] && in_valid) begin
        //data_r[(i+1)*DataBits-1 -: DataBits] <= in_data;
        data_r[i*DataBits +: DataBits] <= in_data;
      end
    end

    if (rst) begin
      count <= 1;
    end

  end

  assign in_ready   = last ? out_ready  : 1;
  assign out_valid  = last ? in_valid : 0;
  assign out_data   = {in_data, data_r};



endmodule
