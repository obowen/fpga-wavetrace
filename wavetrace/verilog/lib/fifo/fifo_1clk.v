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
// Synchronous (1-Clock) FIFO
// -----------------------------------------------------------------------------
// This is a "look-ahead" style fifo, meaning rd_data will contain valid fifo
// data anytime the fifo is not empty.
//
// NOTE: This FIFO does *not* have overflow or underflow protection.
//
// -----------------------------------------------------------------------------
module fifo_1clk(clk, rst, wr_en, wr_data, full, rd_en, rd_data, empty, used);
`include "util.vh"
  parameter                 Width     = 8;
  parameter                 Depth     = 128;  // can be non-power of two
  //
  localparam                AddrBits  = clog2(Depth);
  localparam                UsedBits  = clog2(Depth+1);
  // ---------------------------------------------------------------------------
  input                     clk;
  input                     rst;
  //
  input                     wr_en;
  input  [Width-1:0]        wr_data;
  output                    full;
  //
  input                     rd_en;
  output [Width-1:0]        rd_data;
  output reg                empty;
  //
  output reg [UsedBits-1:0] used;
  // ---------------------------------------------------------------------------

  // helper funtion to increment a pointer with wrap-around and phase toggle
  function automatic [AddrBits:0] inc(input en, input phase,
                                      input [AddrBits-1:0] addr);
    reg [AddrBits-1:0] addr_n;
    reg                phase_n;
    begin
      addr_n  = addr;
      phase_n = phase;
      if (en) begin
        if (addr == Depth-1) begin
          addr_n  = 0;
          phase_n = ~phase;
        end else begin
          addr_n = addr + 1;
        end
      end
      inc = {phase_n, addr_n};
    end
  endfunction

  // -----------------------
  // Read and Write Pointers
  // -----------------------
  reg  [AddrBits-1:0]  rd_addr,     wr_addr;
  wire [AddrBits-1:0]  rd_addr_n,   wr_addr_n;
  reg                  rd_phase,    wr_phase;
  wire                 rd_phase_n,  wr_phase_n;

  assign {rd_phase_n, rd_addr_n} = inc(rd_en, rd_phase, rd_addr);
  assign {wr_phase_n, wr_addr_n} = inc(wr_en, wr_phase, wr_addr);

  always @(posedge clk) begin
    if (rst) begin
      {rd_phase, rd_addr} <= 0;
      {wr_phase, wr_addr} <= 0;
    end else begin
      {rd_phase, rd_addr} <= {rd_phase_n, rd_addr_n};
      {wr_phase, wr_addr} <= {wr_phase_n, wr_addr_n};
    end
  end

  // ---
  // RAM
  // ---
  ram_1c_1r_1w #(
    .Depth (Depth),
    .Width (Width),
    .ReportCollision(0))
  ram (
    .clk     (clk),
    .wr_en   (wr_en),
    .wr_addr (wr_addr),
    .wr_data (wr_data),
    .rd_addr (rd_addr_n), // use next read-address for "look-ahead" behavior
    .rd_data (rd_data)
    );

  // -------------------
  // Full, Empty & Used
  // -------------------
  // NOTE: We delay empty by one cycle after a write to avoid using read data
  //       from a potential R/W collision cycle. We also use the 'next' read
  //       pointer to ensure we're not delaying assertions of the empty flag.
  wire   empty_i  = (rd_addr_n == wr_addr && rd_phase_n == wr_phase);
  assign full     = (rd_addr   == wr_addr && rd_phase   != wr_phase);

  always @(posedge clk) begin
    if (rst) begin
      empty <= 1;
      used  <= 0;
    end else begin
      used  <= used + wr_en - rd_en;
      empty <= empty_i;
    end
  end

endmodule
