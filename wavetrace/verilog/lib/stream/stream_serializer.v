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
// Stream Serializer
// -----------------------------------------------------------------------------
// Serializes each valid input cycle into multiple valid output cycles.
//
// NOTE: Data ordering is Little Endian (LSB position is output on 1st cycle)
//
// -----------------------------------------------------------------------------
module stream_serializer #(
  parameter DataBits = 8,
  parameter Ratio = 2)
(
  input                       clk,
  input                       rst,
  //
  input                       in_valid,
  output                      in_ready,
  input [Ratio*DataBits-1:0]  in_data,
  //
  output                      out_valid,
  input                       out_ready,
  output [DataBits-1:0]       out_data
);

  reg [Ratio-1:0]              count;
  reg [(Ratio-1)*DataBits-1:0] data_r;

  always @(posedge clk) begin

    // one hot counter to track serialization cycle
    if (out_valid & out_ready) begin
      count <= (count[Ratio-1]) ? 1 : count << 1;
    end

    // data registers
    if (out_ready) begin
      if (count[0] & in_valid) begin
        // parallel load of all but the LSB element
        data_r <= in_data[Ratio*DataBits-1:DataBits];
      end else begin
        // shift data regs
        data_r <= data_r >> DataBits;
      end
    end

    if (rst) begin
      count <= 1;
    end
  end

  assign in_ready  = count[0] ? out_ready : 1'b0;
  assign out_valid = count[0] ? in_valid  : 1'b1;
  assign out_data  = count[0] ? in_data[DataBits-1:0] : data_r[DataBits-1:0];

endmodule
