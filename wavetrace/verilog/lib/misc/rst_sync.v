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
// ---------------------------------------------------------------------------
// Reset Synchronizer
// ---------------------------------------------------------------------------
// Detects an asynchronous pulse on the 'arst' input, asynchrounously asserts
// the 'rst' output, and then synchronously deasserts the 'rst' output.
//
// ---------------------------------------------------------------------------
module rst_sync(
  input      arst,
  input      clk,
  output reg rst);

  reg        rsync;
  always @(posedge clk, posedge arst) begin
    if (arst) {rst, rsync} <= 2'b11;
    else      {rst, rsync} <= {rsync, 1'b0};
  end

endmodule
