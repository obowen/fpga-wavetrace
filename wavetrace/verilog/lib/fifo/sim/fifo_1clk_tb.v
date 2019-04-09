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
// Synchronous (1-Clock) FIFO Testbench
// -----------------------------------------------------------------------------
//
// -----------------------------------------------------------------------------
module fifo_1clk_tb;

  // ---------------
  // Clock and Reset
  // ---------------
  wire clk, rst;
  clock_gen clkgen(
    .clk (clk),
    .rst (rst));

  // -------------
  // Stream Source
  // -------------
  wire       din_valid, din_ready;
  wire [7:0] din_data;
  stream_source #(
    .Filename    ("in.dat"),
    .NumSymbols (1),
    .SymbolBits ({32'd8}))
  src (
    .clk       (clk),
    .rst       (rst),
    .dout_ready(din_ready),
    .dout_valid(din_valid),
    .dout_data (din_data));

  // ----
  // FIFO
  // ----
  wire        dout_valid, dout_ready;
  wire [7:0]  dout_data;

  stream_fifo_1clk #(
    .Width    (8),
    .Depth    (100))
  fifo(
    .clk       (clk),
    .rst       (rst),
    //
    .din_valid (din_valid),
    .din_ready (din_ready),
    .din_data  (din_data),
    //
    .dout_valid(dout_valid),
    .dout_ready(dout_ready),
    .dout_data (dout_data),
    //
    .used ( ));

  // -----------
  // Stream Sink
  // -----------
  wire       done, err;
  stream_sink #(
    .FilenameDump ("out.dat"),
    .FilenameRef  ("ref.dat"),
    .CheckData    (1),
    .NumSymbols   (1),
    .SymbolBits   ({32'd8}))
  snk (
    .clk       (clk),
    .rst       (rst),
    .din_ready (dout_ready),
    .din_valid (dout_valid),
    .din_data  (dout_data),
    .done      (done),
    .err       (err));

  // ----------
  // Monitoring
  // ----------
  reg        finished;
  always @(posedge clk) begin
    if (!finished) begin
      if (done) begin
        if (err)
          $display("***SIMULATION FAILED***");
        else
          $display("***SIMULATION PASSED***");
        //$finish
        finished = 1;
      end
    end
    if (rst)
      finished = 0;
  end


endmodule
