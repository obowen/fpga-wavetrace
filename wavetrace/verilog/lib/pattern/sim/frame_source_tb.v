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
// Frame Source / Sink Testbench
// -----------------------------------------------------------------------------
//
// -----------------------------------------------------------------------------
`timescale 1ns/100ps
`default_nettype none

module frame_source_tb;

  // ---------------
  // Clock and Reset
  // ---------------
  wire clk, rst;
  clock_gen clkgen(
    .clk (clk),
    .rst (rst));

  // -------------
  // Frame Source
  // -------------
  wire src_valid, src_ready, src_eof;
  wire [7:0] src_data;
  frame_source #(
    .GoDefault(1))
  src(
    .clk        (clk),
    .rst        (rst),
    //
    .cfg_paddr  (5'b0),
    .cfg_pwrite (1'b0),
    .cfg_pwdata (32'b0),
    .cfg_psel   (1'b0),
    .cfg_penable(1'b0),
    .cfg_pready (),
    .cfg_prdata (),
    .cfg_pslverr(),
    .cfg_irq    (),
    //
    .dout_ready (src_ready),
    .dout_valid (src_valid),
    .dout_eof   (src_eof),
    .dout_data  (src_data));

  // ----------
  // Rate Ctrl
  // ----------
  wire       rate_valid, rate_ready, rate_active;
  rate_ctrl #(
    .THROUGHPUT (50))
  rate(
    .clk    (clk),
    .rst    (rst),
    .active (rate_active),
    .ack    (src_valid & src_ready));

  assign rate_valid = (rate_active) ? src_valid  : 1'b0;
  assign src_ready  = (rate_active) ? rate_ready : 1'b0;

  // -------------
  // insert errors
  // -------------
  wire       ins_valid, ins_ready, ins_eof;
  wire [7:0] ins_data;
  insert_errors
  ins_err(
    .clk        (clk),
    .rst        (rst),
    //
    .cfg_paddr  (5'b0),
    .cfg_pwrite (1'b0),
    .cfg_pwdata (32'b0),
    .cfg_psel   (1'b0),
    .cfg_penable(1'b0),
    .cfg_pready (),
    .cfg_prdata (),
    .cfg_pslverr(),
    //
    .din_ready  (rate_ready),
    .din_valid  (rate_valid),
    .din_eof    (src_eof),
    .din_data   (src_data),
    //
    .dout_ready (ins_ready),
    .dout_valid (ins_valid),
    .dout_eof   (ins_eof),
    .dout_data  (ins_data));

  // -----------
  // Frame Sink
  // -----------
  frame_sink
  snk(
    .clk        (clk),
    .rst        (rst),
    //
    .cfg_paddr  (5'b0),
    .cfg_pwrite (1'b0),
    .cfg_pwdata (32'b0),
    .cfg_psel   (1'b0),
    .cfg_penable(1'b0),
    .cfg_pready (),
    .cfg_prdata (),
    .cfg_pslverr(),
    .cfg_irq    (),
    //
    .din_ready  (ins_ready),
    .din_valid  (ins_valid),
    .din_eof    (ins_eof),
    .din_data   (ins_data));

endmodule


