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
// -----------------------------------------------------------------
// Clock Mux
// -----------------------------------------------------------------
// Glitch free clock switching for unrelated clocks.
//
// implementation based on this article:
// http://www.eetimes.com/document.asp?doc_id=1202359
//
// -----------------------------------------------------------------
module clk_mux (
  input  in0_clk,
  input  in0_arst,
  input  in1_clk,
  input  in1_arst,
  input  sel,
  output out_clk);

  reg    sync0_p, sync0_n;
  reg    sync1_p, sync1_n;

  always @(posedge in0_clk or posedge in0_arst) begin
    if (in0_arst)
      sync0_p <= 1'b0;
    else
      sync0_p <= ~sel & ~sync1_n;
  end
  always @(negedge in0_clk or posedge in0_arst) begin
    if (in0_arst)
      sync0_n <= 1'b0;
    else
      sync0_n <= sync0_p;
  end

  always @(posedge in1_clk or posedge in1_arst) begin
    if (in1_arst)
      sync1_p <= 1'b0;
    else
      sync1_p <= sel & ~sync0_n;
  end
  always @(negedge in1_clk or posedge in1_arst) begin
    if (in1_arst)
      sync1_n <= 1'b0;
    else
      sync1_n <= sync1_p;
  end

  assign out_clk = (in0_clk & sync0_n) | (in1_clk & sync1_n);

endmodule
