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
// Clock and Reset Generator for Simulation
// -----------------------------------------------------------------------------
//
// -----------------------------------------------------------------------------
`timescale 1ns/100ps

module clock_gen (
  output reg clk,
  output reg rst);

  initial begin
    clk = 0;
    #5 forever clk = #5 ~clk;
  end

  integer i;
  initial begin
    rst <= 1;
    for (i=1; i<3; i=i+1)
      @(negedge clk);
    rst <= 0;
  end

endmodule

