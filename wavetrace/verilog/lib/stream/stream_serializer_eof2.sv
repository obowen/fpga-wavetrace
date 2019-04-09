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
// Stream Serializer (with EOF) Version 2
// -----------------------------------------------------------------------------
// Serializes each valid input cycle into multiple valid output cycles.
//
// Unlike stream_serializer_eof version 1:
//
// The input stream takes in one EOF bit per serialization word, indicating
// which slice of the input vector represents the EOF element. The serialization
// cycle will complete when the EOF slice has been output, so the final input
// data element may produce a variable number of output elements, depending on
// which EOF bit is set.
//
// NOTE: Data ordering is Little Endian (LSB position is output on 1st cycle)
//
// -----------------------------------------------------------------------------
module stream_serializer_eof2 #(
  parameter DataBits = 8,
  parameter Ratio = 2)  // Serialization ratio, minimum of two
(
  input                      clk,
  input                      rst,
  //
  input                      in_valid,
  output                     in_ready,
  input [Ratio*DataBits-1:0] in_data,
  input [Ratio-1:0]          in_eof,
  //
  output                     out_valid,
  input                      out_ready,
  output [DataBits-1:0]      out_data,
  output                     out_eof
);

  logic [Ratio-1:0]              count;
  logic [(Ratio-1)*DataBits-1:0] data_r;
  logic [Ratio-2:0]              eof_r;

  always_ff @(posedge clk) begin

    // One hot counter to track serialization cycle
    if (out_valid & out_ready) begin
      count <= (count[Ratio-1] | out_eof) ? 1 : count << 1;
    end

    // Data and EOF registers
    if (out_ready) begin
      if (count[0] & in_valid) begin
        // Parallel load of all but the LSB element
        data_r <= in_data[Ratio*DataBits-1:DataBits];
        eof_r  <= in_eof[Ratio-1:1];
      end else begin
        // Shift data regs
        data_r <= data_r >> DataBits;
        eof_r  <= eof_r  >> 1;
      end
    end

    if (rst) begin
      count <= 1;
    end
  end

  assign in_ready  = count[0] ? out_ready : 1'b0;
  assign out_valid = count[0] ? in_valid  : 1'b1;
  assign out_data  = count[0] ? in_data[DataBits-1:0] : data_r[DataBits-1:0];
  assign out_eof   = count[0] ? in_eof[0] : eof_r[0];

endmodule
