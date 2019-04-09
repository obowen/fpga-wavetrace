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
// Stream Deserializer (with EOF) Version 2
// -----------------------------------------------------------------------------
// Converts a serial stream of valid data elements into a parallel bus output on
// a single valid cycle.
//
// Unlike stream_deserializer_eof version 1:
//
// The arrival of the EOF signal will force the completion of the current word
// word, regardless of what deserialization cycle we're on. The output EOF vector
// will contain a '1' in the bit-position that corresponds to the slice in the
// output vector that contains the final input element. Any 'unused' slices in
// the final output vector should be treated as don't-care (they will contain
// the previous cycle's data).
//
// For example, if the deserializaiton ratio is two:
//  * If an incoming frame contains three words, the output stream will contain
//    two words and 'out_eof[0]' will be high on the final output cycle.
//  * If the incoming frame contains four words, the output stream will contain
//    two words and 'out_eof[1]' will be high on the final output cycle.
//
// Also, this block adds 1-cycle of latency to the stream compared to version 1.
//
// NOTE: Data ordering is Little Endian (1st element received is output in
//       LSB position)
//
// -----------------------------------------------------------------------------
module stream_deserializer_eof2 #(
  parameter DataBits = 8,
  parameter Ratio    = 2)  // Deserialization ratio, minimum of 2
(
  input                             clk,
  input                             rst,
  //
  input                             in_valid,
  output                            in_ready,
  input [DataBits-1:0]              in_data,
  input                             in_eof,
  //
  output logic                      out_valid,
  input                             out_ready,
  output logic [Ratio*DataBits-1:0] out_data,
  output logic [Ratio-1:0]          out_eof
);

  logic [$clog2(Ratio)-1:0] count;

  wire last = (count == Ratio - 1) | in_eof;

  always_ff @(posedge clk) begin
    if (in_valid & in_ready) begin
      count <= (last) ? '0 : count + 1;
      out_data[count*DataBits +: DataBits] <= in_data;
      out_eof[count]  <= in_eof;
    end

    if (last & in_valid)
      out_valid <= '1;
    else if (out_ready)
      out_valid <= '0;

    if (rst)
      count <= '0;
  end

  assign in_ready = ~out_valid | out_ready;

endmodule
