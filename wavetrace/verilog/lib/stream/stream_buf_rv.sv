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
// Stream Buffer Type-R Plus Type-V
// -----------------------------------------------------------------------------
// Instantiates a stream_buf_r, followed by a stream buf_v, such that all
// outputs are registered.
//
// -----------------------------------------------------------------------------
module stream_buf_rv #(
  parameter DataBits = 8)
  ( input                 clk,
    input                 rst,
    //
    input                 in_valid,
    output                in_ready,
    input [DataBits-1:0]  in_data,
    //
    output                out_valid,
    input                 out_ready,
    output [DataBits-1:0] out_data
);

  wire                bufr_valid, bufr_ready;
  wire [DataBits-1:0] bufr_data;
  stream_buf_r #(
    .DataBits(DataBits))
  bufr(
    .clk      (clk),
    .rst      (rst),
    .in_valid (in_valid),
    .in_ready (in_ready),
    .in_data  (in_data),
    .out_valid(bufr_valid),
    .out_ready(bufr_ready),
    .out_data (bufr_data));

  stream_buf_v #(
    .DataBits (DataBits))
  bufv(
    .clk      (clk),
    .rst      (rst),
    .in_valid (bufr_valid),
    .in_ready (bufr_ready),
    .in_data  (bufr_data),
    .out_valid(out_valid),
    .out_ready(out_ready),
    .out_data (out_data));

endmodule

