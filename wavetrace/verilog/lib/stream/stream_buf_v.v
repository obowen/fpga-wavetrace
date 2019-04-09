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
// ------------------------------------------------------------------
// Stream Buffer Type-V
// ------------------------------------------------------------------
// Acts as a 1-deep FIFO for a data stream. Both 'out_valid' and
// 'out_data' are registered, but 'in_ready' is not registered.
//
// ------------------------------------------------------------------
module stream_buf_v #(
  parameter DataBits = 8)
  ( input                     clk,
    input                     rst,
    //
    input                     in_valid,
    output                    in_ready,
    input [DataBits-1:0]      in_data,
    //
    output reg                out_valid,
    input                     out_ready,
    output reg [DataBits-1:0] out_data
);

  assign in_ready  = ~out_valid | out_ready;

  always @(posedge clk) begin

    // valid register, with reset
    if (rst) begin
      out_valid <= 1'b0;
    end else begin
      out_valid <= ~in_ready | in_valid;
    end

    // data register
    if (in_valid & in_ready) begin
      out_data <= in_data;
    end

  end

endmodule

