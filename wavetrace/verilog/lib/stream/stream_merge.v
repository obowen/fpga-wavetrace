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
// Stream Merge
// ---------------------------------------------------------------------
// Merges two or more input streams into a single output stream.
//
// ---------------------------------------------------------------------
module stream_merge #(
  parameter NumStreams = 2)
  (
    input      [NumStreams-1:0] in_valid,
    output reg [NumStreams-1:0] in_ready,
    //
    output                      out_valid,
    input                       out_ready
  );

  // out_valid is high when all in_valids are high
  assign out_valid  = &in_valid;

  // in_ready is only high when out_ready is high as well as all of
  // the other in_valids
  reg       other_valids;
  integer   i, j;
  always @(*) begin
    for (i=0; i < NumStreams; i=i+1) begin
      other_valids = 1'b1;
      for (j=0; j < NumStreams; j=j+1)
        if (j != i)
          other_valids = other_valids & in_valid[j];

      in_ready[i] = other_valids & out_ready;
    end
  end

endmodule

