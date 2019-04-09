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
// LFSR Source / Sink Testbench
// -----------------------------------------------------------------------------
//
// -----------------------------------------------------------------------------
`default_nettype none

module lfsr_tb;

  localparam DataBits = 32;

  // ---------------
  // Clock and Reset
  // ---------------
  wire clk, rst;
  clock_gen clkgen(
    .clk (clk),
    .rst (rst));

  // -----------
  // LFSR Source
  // -----------
  wire                din_valid, din_ready, din_eof;
  wire [DataBits-1:0] din_data;

  lfsr_source #(
    .DataBits  (DataBits),
    .GoDefault (1),
    .MaxLength (64))
  lfsr_src (
    //
    .cfg_clk     (clk),
    .cfg_rst     (rst),
    .cfg_paddr   (5'b0),
    .cfg_pwrite  (1'b0),
    .cfg_pwdata  (32'b0),
    .cfg_psel    (1'b0),
    .cfg_penable (1'b0),
    .cfg_pready  ( ),
    .cfg_prdata  ( ),
    .cfg_pslverr ( ),
    //
    .dout_clk  (clk),
    .dout_rst  (rst),
    .dout_ready(din_ready),
    .dout_valid(din_valid),
    .dout_data (din_data),
    .dout_eof  (din_eof));

  // insert some errors
  reg [15:0] count;
  always @(posedge clk) begin
    if (rst) begin
      count <= 0;
    end else begin
      count <= count + 1;
    end
  end

  reg [DataBits-1:0] din_err;
  always @(*) begin
    din_err             = din_data;
    // invert some bits
    din_err[0]          = !din_data[0];
    din_err[1]          = !din_data[1];
    din_err[5]          = !din_data[5];
    din_err[DataBits-1] = !din_data[DataBits-1];
    din_err[DataBits-4] = !din_data[DataBits-4];
    din_err[DataBits-5] = !din_data[DataBits-5];
  end

  wire [DataBits-1:0] din_data_i =  (count[2:0] == 7) ? din_err : din_data;

  // ---------
  // LFSR Sink
  // ---------
  lfsr_sink #(
    .DataBits (DataBits))
  lfsr_snk (
    //
    .cfg_clk     (clk),
    .cfg_rst     (rst),
    .cfg_paddr   (5'b0),
    .cfg_pwrite  (1'b0),
    .cfg_pwdata  (32'b0),
    .cfg_psel    (1'b0),
    .cfg_penable (1'b0),
    .cfg_pready  ( ),
    .cfg_prdata  ( ),
    .cfg_pslverr ( ),
    //
    .din_clk  (clk),
    .din_rst  (rst),
    .din_ready(din_ready),
    .din_valid(din_valid),
    .din_data (din_data_i),
    .din_eof  (din_eof));


endmodule
