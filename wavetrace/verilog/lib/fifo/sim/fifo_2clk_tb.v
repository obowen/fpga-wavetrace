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
// Asynchronous (2-Clock) FIFO Testbench
// -----------------------------------------------------------------------------
//
// -----------------------------------------------------------------------------
module fifo_2clk_tb;

  // ---------------
  // Clock and Reset
  // ---------------
  reg din_clk, dout_clk;
  reg rst;

  initial begin
    din_clk = 0;
    #3 forever din_clk = #3 ~din_clk;
  end

  initial begin
    dout_clk = 0;
    #4 forever dout_clk = #4 ~dout_clk;
  end

  integer i;
  initial begin
    rst <= 1;
    for (i=1; i<3; i=i+1)
      @(negedge din_clk);
    rst <= 0;
  end

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
    .clk       (din_clk),
    .rst       (rst),
    .dout_ready(din_ready),
    .dout_valid(din_valid),
    .dout_data (din_data));

  // ----
  // FIFO
  // ----
  wire        dout_valid, dout_ready;
  wire [7:0]  dout_data;

  stream_fifo_2clk #(
    .Width    (8),
    .Depth    (64))
  fifo(
    .din_clk   (din_clk),
    .din_rst   (rst),
    .din_valid (din_valid),
    .din_ready (din_ready),
    .din_data  (din_data),
    .din_free  ( ),
    //
    .dout_clk  (dout_clk),
    .dout_rst  (rst),
    .dout_valid(dout_valid),
    .dout_ready(dout_ready),
    .dout_data (dout_data),
    .dout_used ( ));

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
    .clk       (dout_clk),
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
  always @(posedge dout_clk) begin
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
