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
// Stream Deserializer (with EOF)
// -----------------------------------------------------------------------------
// Converts a serial stream of valid data elements into a parallel bus output on
// a single valid cycle.
//
// The EOF signal is taken from the final deserialization cycle.
//
// NOTE: Data ordering is Little Endian (1st element received is output in
//        LSB position)
//
// -----------------------------------------------------------------------------
module stream_deserializer_eof #(
  parameter DataBits = 8,
  parameter Ratio    = 2)
(
  input                           clk,
  input                           rst,
  //
  input                           in_valid,
  output                          in_ready,
  input [DataBits-1:0]            in_data,
  input                           in_eof,
  //
  output                          out_valid,
  input                           out_ready,
  output reg [Ratio*DataBits-1:0] out_data,
  output                          out_eof
);

  wire [Ratio*(DataBits+1)-1:0] out_data_i;
  stream_deserializer #(
    .DataBits (DataBits+1),
    .Ratio    (Ratio))
  ser (
    .rst       (rst),
    .clk       (clk),
    .in_valid  (in_valid),
    .in_ready  (in_ready),
    .in_data   ({in_eof, in_data}),
    .out_valid (out_valid),
    .out_ready (out_ready),
    .out_data  (out_data_i));

  integer i;
  always @(*) begin
    for (i=0; i < Ratio; i=i+1) begin
      out_data[i*DataBits +: DataBits] = out_data_i[i*(DataBits+1) +: DataBits];
    end
  end

  assign out_eof = out_data_i[Ratio*(DataBits+1)-1];

endmodule
