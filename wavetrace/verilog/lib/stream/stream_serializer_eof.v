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
// Stream Serializer (with EOF)
// -----------------------------------------------------------------------------
// Serializes each valid input cycle into multiple valid output cycles.
//
// The EOF signal is output on the final serialization cycle.
//
// NOTE: Data ordering is Little Endian (LSB position is output on 1st cycle)
//
// -----------------------------------------------------------------------------
module stream_serializer_eof #(
  parameter DataBits = 8,
  parameter Ratio = 2)
(
  input                      clk,
  input                      rst,
  //
  input                      in_valid,
  output                     in_ready,
  input [Ratio*DataBits-1:0] in_data,
  input                      in_eof,
  //
  output                     out_valid,
  input                      out_ready,
  output [DataBits-1:0]      out_data,
  output                     out_eof
);

  // Expand the input vector by inserting zeros after each element, but use the 'eof' bit for
  // the last data element so that it gets output on the final serialization cycle.
  reg [Ratio*(DataBits+1)-1:0] in_data_i;
  reg                          fill;
  integer                      i;
  always @(*) begin
    for (i=0; i < Ratio; i=i+1) begin
      fill = (i==Ratio-1) ? in_eof : 1'b0;
      in_data_i[i*(DataBits+1) +: (DataBits+1)] = {fill, in_data[i*DataBits +: DataBits]};
    end
  end

  // serialize the expanded input vector
  stream_serializer #(
    .DataBits (DataBits+1),
    .Ratio    (Ratio))
  ser (
    .rst       (rst),
    .clk       (clk),
    .in_valid  (in_valid),
    .in_ready  (in_ready),
    .in_data   (in_data_i),
    .out_valid (out_valid),
    .out_ready (out_ready),
    .out_data  ({out_eof, out_data}));

endmodule
