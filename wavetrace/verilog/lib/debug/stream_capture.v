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
// Stream Capture
// -----------------------------------------------------------------------------
// Acts as a stream spy, recording the data of each transaction into a block-ram
// based memory. The buffer is accessible by software via an APB interface.
//
// APB registers enable or disable data capture and can be used to reset the
// data buffer pointers.
//
// -----------------------------------------------------------------------------
module stream_capture (clk, rst, din_data, din_valid, din_ready,
                       cfg_paddr, cfg_psel, cfg_penable, cfg_pwrite,
                       cfg_pwdata, cfg_pready, cfg_prdata, cfg_pslverr);
`include "util.vh"
  parameter  DataBits    = 8;
  parameter  MemDepth    = 1024;
  localparam MemAddrBits = clog2(MemDepth);
  // ---------------------------------------------------------------------------
  input                   clk;
  input                   rst;
  //
  input [DataBits-1:0]    din_data;
  input                   din_valid;
  input                   din_ready;
  //
  input [2+MemAddrBits:0] cfg_paddr;
  input                   cfg_psel;
  input                   cfg_penable;
  input                   cfg_pwrite;
  input [31:0]            cfg_pwdata;
  output reg              cfg_pready;
  output reg [31:0]       cfg_prdata;
  output                  cfg_pslverr;
  // ---------------------------------------------------------------------------

  // -----------
  // Address Map
  // -----------
  // NOTE: Addresses 0 to Depth-1 are used to read the contents of the memory.
  localparam EnableAddr = 2**MemAddrBits + 0, // RW: enables data capture
             ResetAddr  = 2**MemAddrBits + 1, // RW: resets write-pointer and counters
             CountAddr  = 2**MemAddrBits + 2, // RO: counts number of transactions captured
             WPtrAddr   = 2**MemAddrBits + 3; // RO: current value of write pointer

  // --------------
  // APB Registers
  // --------------
  assign cfg_pslverr = 0; // unused

  wire [DataBits-1:0]    mem_data;

  reg                    enable, soft_rst, mem_rd;
  reg [15:0]             count;
  reg [MemAddrBits-1:0]  wptr;

  always @(posedge clk) begin :cfg
    integer addr_i;
    addr_i = cfg_paddr >> 2; // convert to word address

    // defaults
    mem_rd     <= 0;
    cfg_pready <= 0;

    if (cfg_psel && !cfg_penable) begin
      // register writing
      if (cfg_pwrite) begin
        cfg_pready <= 1;
        case (addr_i)
          EnableAddr:   enable   <= cfg_pwdata[0];
          ResetAddr:    soft_rst <= cfg_pwdata[0];
        endcase

      // register reading
      end else begin
        if (addr_i < MemDepth) begin
          mem_rd  <= 1;
        end else begin
          cfg_pready <= 1;
          case (addr_i)
            EnableAddr: cfg_prdata <= enable;
            ResetAddr:  cfg_prdata <= soft_rst;
            CountAddr:  cfg_prdata <= count;
            WPtrAddr:   cfg_prdata <= wptr;
          endcase
        end
      end
    end

    // delay memory reads by 1 cycle to account for latency through RAM
    if (mem_rd) begin
      cfg_prdata <= mem_data;
      cfg_pready <= 1;
    end

    if (rst) begin
      enable   <= 0;
      soft_rst <= 0;
    end
  end

  // -------------------
  // Data Capture Memory
  // -------------------
  wire wen  = enable & din_valid & din_ready;

  always @(posedge clk) begin
    if (wen) begin
      wptr  <= (wptr == MemDepth-1) ? 0 : wptr + 1;
      count <= count + 1;
    end
    if (rst | soft_rst) begin
      wptr  <= 0;
      count <= 0;
    end
  end

  ram_1r_1w #(
    .Width (DataBits),
    .Depth (MemDepth))
  mem(
    .clk     (clk),
    .wr_en   (wen),
    .wr_addr (wptr),
    .wr_data (din_data),
    .rd_addr (cfg_paddr[MemAddrBits+2-1:2]), // use word address
    .rd_data (mem_data));

endmodule
