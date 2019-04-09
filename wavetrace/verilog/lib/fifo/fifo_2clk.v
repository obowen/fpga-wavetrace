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
// Asynchronous (2-Clock) FIFO
// -----------------------------------------------------------------------------
// An asynchrnous dual clock FIFO with 'free' and 'used' outputs. This is a
// lookahead style FIFO i.e. the next data element is made available on the
// rd_data bus and held until the cycle after 'rd_en' is asserted.
//
// This FIFO does *not* have overflow or underflow protection. The user logic
// is responsible for ensuring that 'wr_en' is not asserted when full and that
// 'rd_en' is not asserted when 'empty'.
//
// The internal functionality of this asynchronous fifo is based on the design
// described in the paper: "Simulation and Synthesis Techniques for Asyncrhonous
// Fifo Design" by Cliff Cummings.
// http://www.sunburst-design.com/papers/CummingsSNUG2002SJ_FIFO1.pdf
//
// Key difference between this implemenation and the design by Cliff Cummings:
//  - A synchronous RAM is used instead of an asynchronous RAM to more easily
//    map to different vendors FPGA block-RAMs.
//  - Fifo usage counts are added to the read and write interfaces.
//  - Overflow and underflow protecion has been removed.
//  - A synchronous reset is used for most flops, in particular the address
//    registers for the RAM are reset synchronously to avoid critical warnings
//    with FGPA tools (eg. Vivado). The gray code registers are still reset
//    asynchronously to avoid using uninitialized values in the opposite clock
//    domain if the read and write resets occur at different times.
//
// -----------------------------------------------------------------------------
module fifo_2clk(wr_clk, wr_rst, wr_en, wr_data, wr_free, wr_full,
                 rd_clk, rd_rst, rd_en, rd_data, rd_used, rd_empty);
`include "util.vh"
`include "graycode.vh"
  parameter              Width     = 8;
  parameter              Depth     = 128; // must be power of 2!
  localparam             AddrBits  = clog2(Depth);
  localparam             UsedBits  = clog2(Depth+1);
  // ------------------------------------------------------------------
  input                     wr_clk;
  input                     wr_rst;
  input                     wr_en;
  input      [Width-1:0]    wr_data;
  output reg [UsedBits-1:0] wr_free;
  output reg                wr_full;
  //
  input                     rd_clk;
  input                     rd_rst;
  input                     rd_en;
  output [Width-1:0]        rd_data;
  output reg [UsedBits-1:0] rd_used;
  output reg                rd_empty;
  // ------------------------------------------------------------------

  // ----------------------------------------------
  // Read and Write Pointers (Binary and Gray code)
  // ----------------------------------------------
  wire [AddrBits:0] wbin, wbin_n, wgray, wgray_n,
                          rbin_n, rgray, rgray_n;
  fifo_ptr #(
    .AddrBits(AddrBits))
  wptr (
    .clk       (wr_clk),
    .rst       (wr_rst),
    .inc       (wr_en),
    .pbin      (wbin),
    .pbin_next (wbin_n),
    .pgray     (wgray),
    .pgray_next(wgray_n));

  fifo_ptr #(
    .AddrBits(AddrBits))
  rptr (
    .clk       (rd_clk),
    .rst       (rd_rst),
    .inc       (rd_en),
    .pbin      ( ),
    .pbin_next (rbin_n),
    .pgray     (rgray),
    .pgray_next(rgray_n));

  // -----------------------------
  // Clock Crossing Sync Registers
  // -----------------------------
  // These registers move the Gray pointers between clock domains
  reg [AddrBits:0]  rgray_rr, rgray_r,
                    wgray_rr, wgray_r;
  wire [AddrBits:0] rbin_rr, wbin_rr;

  always @(posedge wr_clk)
    if (wr_rst) {rgray_rr, rgray_r} <= 0;
    else        {rgray_rr, rgray_r} <= {rgray_r, rgray};

  always @(posedge rd_clk)
    if (rd_rst) {wgray_rr, wgray_r} <= 0;
    else        {wgray_rr, wgray_r} <= {wgray_r, wgray};

  assign wbin_rr = gray2bin(wgray_rr, AddrBits + 1);
  assign rbin_rr = gray2bin(rgray_rr, AddrBits + 1);

  // ------------------------
  // Full Flag and Free Count
  // ------------------------
  always @(posedge wr_clk) begin
    if (wr_rst) begin
      wr_full <= 0;
      wr_free <= Depth;
    end else begin
      // determine when full, uses simplified version of this code:
      // wr_full  <= wgray_n[AddrBits]     != rgray_rr[AddrBits]   &&
      //             wgray_n[AddrBits-1]   != rgray_rr[AddrBits-1] &&
      //             wgray_n[AddrBits-2:0] != rgray_rr[AddrBits-2:0];
      wr_full <= (wgray_n == {~rgray_rr[AddrBits:AddrBits-1],
                               rgray_rr[AddrBits-2:0]});

      // calculate free space in fifo
      wr_free <= rbin_rr[AddrBits-1:0] - wbin_n[AddrBits-1:0] +
                 ((rbin_rr[AddrBits] ~^ wbin_n[AddrBits]) << AddrBits);
    end
  end

  // -------------------------
  // Empty Flag and Used Count
  // -------------------------
  always @(posedge rd_clk) begin
    if (rd_rst) begin
      rd_empty <= 1;
      rd_used  <= 0;
    end else begin
      rd_empty <= (rgray_n == wgray_rr);
      rd_used  <= wbin_rr[AddrBits-1:0] - rbin_n[AddrBits-1:0] +
                  ((wbin_rr[AddrBits] ^ rbin_n[AddrBits]) << AddrBits);
    end
  end

  // --------------
  // Dual Clock RAM
  // --------------
  wire [AddrBits-1:0] wr_addr, rd_addr;

  assign wr_addr = wbin[AddrBits-1:0];
  assign rd_addr = rbin_n[AddrBits-1:0];  // use 'rbin_n' for lookahead behavior

  ram_2c_1r_1w #(
    .Width(Width),
    .Depth(Depth),
    .ReportCollision(0))
  ram (
    .wr_clk (wr_clk),
    .wr_en  (wr_en),
    .wr_addr(wr_addr),
    .wr_data(wr_data),
    .rd_clk (rd_clk),
    .rd_addr(rd_addr),
    .rd_data(rd_data));

endmodule
