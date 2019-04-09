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
// ---------------------------------------------------------------------
// Stream Split
// ---------------------------------------------------------------------
// Splits an input stream into two or more output streams.
//
// ---------------------------------------------------------------------
module stream_split #(
  parameter NumStreams = 2)
  (
    input                       in_valid,
    output                      in_ready,
    //
    output reg [NumStreams-1:0] out_valid,
    input      [NumStreams-1:0] out_ready
  );

  // in_ready is high when all out_readies are high
  assign in_ready = &out_ready;

  // out_valid is is only high when in_valid is high as well as all of
  // the other out_readies
  reg       other_readys;
  integer   i, j;
  always @(*) begin
    for (i=0; i < NumStreams; i=i+1) begin
      other_readys = 1'b1;
      for (j=0; j < NumStreams; j=j+1)
        if (j != i)
          other_readys = other_readys & out_ready[j];

      out_valid[i] = other_readys & in_valid;
    end
  end

endmodule

