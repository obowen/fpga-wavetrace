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
// Asynchronous Fifo: Pointer Submodule
// -----------------------------------------------------------------------------
// Shared logic for read and write pointers used in an asynchronous fifo.
// Outputs binary and Gray code pointers along with combinatorially driven
// 'next' pointer values. The binary pointer is reset synchronously and the
// Gray code pointer is reset asynchronously (see comments below).
//
// -----------------------------------------------------------------------------
module fifo_ptr #(
  parameter AddrBits = 8)
(
  input                   clk,
  input                   rst,
  input                   inc,         // increment pointer
  output reg [AddrBits:0] pbin,        // binary pointer
  output     [AddrBits:0] pbin_next,   // next binary pointer
  output reg [AddrBits:0] pgray,       // Gray code pointer
  output     [AddrBits:0] pgray_next); // next Gray code pointer

`include "graycode.vh"

  always @(posedge clk) begin
    if (rst) pbin <= 0;
    else     pbin <= pbin_next;
  end

  // We use an asynchronous reset here to avoid using uninitialized data in
  // the opposite clock domain if the read and write resets occur at
  // different times.
  always @(posedge clk or posedge rst) begin
    if (rst) pgray <= 0;
    else     pgray <= pgray_next;
  end

  assign pbin_next  = pbin + inc;
  assign pgray_next = bin2gray(pbin_next);

endmodule
