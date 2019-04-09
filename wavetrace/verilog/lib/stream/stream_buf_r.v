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
// Stream Buffer Type-R
// ---------------------------------------------------------------------
// Acts as a 1-deep FIFO for a data stream and registers the 'in_ready'
// output. Neither 'out_data' nor 'out_valid' are registered. Use this
// block to break up long ready paths for timing purposes.
//
// ---------------------------------------------------------------------
module stream_buf_r #(
  parameter DataBits = 8)
  ( input                  clk,
    input                  rst,
    //
    input                  in_valid,
    output reg             in_ready,
    input  [DataBits-1:0]  in_data,
    //
    output                 out_valid,
    input                  out_ready,
    output  [DataBits-1:0] out_data
);

  reg [DataBits-1:0] data_r;

  always @(posedge clk) begin

    // ready register, reset high
    if (rst) begin
      in_ready <= 1'b1;
    end else begin
      in_ready <= ~out_valid | out_ready;
    end

    // store data when it's valid and the output is not ready
    if (in_ready & in_valid & ~out_ready) begin
      data_r <= in_data;
    end

  end

  // output is valid if we're holding valid data, or if the input is valid
  assign out_valid  = ~in_ready | in_valid;

  // mux between incoming data and stored data
  assign out_data = in_ready ? in_data : data_r;

endmodule

