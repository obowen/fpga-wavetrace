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
// Dma 2-Channel Wrapper
// -----------------------------------------------------------------------------
// Combines a memory-to-stream DMA module and a stream-to-memory DMA module
// into a single AXI master interface
//
// -----------------------------------------------------------------------------
module dma_2chan_wrap #(
  parameter StrmDataBits  = 8,
  parameter MemDataBits   = 64,
  parameter AddrBits      = 32,
  parameter LengthBits    = 16,
  parameter FifoDepth     = 64,
  parameter LenInStrm     = 1)
(
  input                      clk,
  input                      rst,
  // APB Interface for reader (mem2strm)
  input [5:0]                rcfg_paddr,
  input                      rcfg_psel,
  input                      rcfg_penable,
  input                      rcfg_pwrite,
  input [31:0]               rcfg_pwdata,
  output                     rcfg_pready,
  output [31:0]              rcfg_prdata,
  output                     rcfg_pslverr,
  output                     rcfg_irq,
  // APB config interface for writer (strm2mem)
  input [5:0]                wcfg_paddr,
  input                      wcfg_psel,
  input                      wcfg_penable,
  input                      wcfg_pwrite,
  input [31:0]               wcfg_pwdata,
  output                     wcfg_pready,
  output [31:0]              wcfg_prdata,
  output                     wcfg_pslverr,
  output                     wcfg_irq,
  // Input Data Stream
  input                      din_valid,
  output                     din_ready,
  input [StrmDataBits-1:0]   din_data,
  input                      din_eof,
  // Output Data Stream
  output                     dout_valid,
  input                      dout_ready,
  output [StrmDataBits-1:0]  dout_data,
  output                     dout_eof,
  // Write Address Channel
  output                     mst_awvalid,
  input                      mst_awready,
  output [3:0]               mst_awid,
  output [AddrBits-1:0]      mst_awaddr,
  output [3:0]               mst_awlen,
  output [2:0]               mst_awsize,
  output [1:0]               mst_awburst,
  output [1:0]               mst_awlock,
  // Write Data Channel
  output                     mst_wvalid,
  input                      mst_wready,
  output [3:0]               mst_wid,
  output [MemDataBits/8-1:0] mst_wstrb,
  output                     mst_wlast,
  output [MemDataBits-1:0]   mst_wdata,
  // Write Response Channel
  input                      mst_bvalid,
  output                     mst_bready,
  input [3:0]                mst_bid,
  input [1:0]                mst_bresp,
  // Read Address Channel
  output                     mst_arvalid,
  input                      mst_arready,
	output [3:0]               mst_arid,
	output [31:0]              mst_araddr,
	output [3:0]               mst_arlen,
  output [2:0]               mst_arsize,
  output [1:0]               mst_arburst,
  output [1:0]               mst_arlock,
  // Read Data Channel
  input                      mst_rvalid,
  output                     mst_rready,
  input [3:0]                mst_rid,
  input [MemDataBits-1:0]    mst_rdata,
  input [1:0]                mst_rresp,
  input                      mst_rlast);

  // ---------------------
  // DMA Stream-to-Memory
  // ---------------------
  dma_strm2mem #(
    .StrmDataBits  (StrmDataBits),
    .MemDataBits   (MemDataBits),
    .AddrBits      (AddrBits),
    .LengthBits    (LengthBits),
    .FifoDepth     (FifoDepth),
    .LenInStrm     (LenInStrm))
  dma_wr (
    .clk            (clk),
    .rst            (rst),
    //
    .cfg_paddr      (wcfg_paddr),
    .cfg_pwrite     (wcfg_pwrite),
    .cfg_pwdata     (wcfg_pwdata),
    .cfg_psel       (wcfg_psel),
    .cfg_penable    (wcfg_penable),
    .cfg_pready     (wcfg_pready),
    .cfg_prdata     (wcfg_prdata),
    .cfg_pslverr    (wcfg_pslverr),
    .cfg_irq        (wcfg_irq),
    //
    .din_valid      (din_valid),
    .din_ready      (din_ready),
    .din_data       (din_data),
    .din_eof        (din_eof),
    //
    .mst_awvalid    (mst_awvalid),
    .mst_awready    (mst_awready),
    .mst_awid       (mst_awid),
    .mst_awaddr     (mst_awaddr),
    .mst_awlen      (mst_awlen),
    .mst_awsize     (mst_awsize),
    .mst_awlock     (mst_awlock),
    .mst_awburst    (mst_awburst),
    //
    .mst_wvalid     (mst_wvalid),
    .mst_wready     (mst_wready),
    .mst_wid        (mst_wid),
    .mst_wstrb      (mst_wstrb),
    .mst_wlast      (mst_wlast),
    .mst_wdata      (mst_wdata),
    //
    .mst_bvalid     (mst_bvalid),
    .mst_bready     (mst_bready),
    .mst_bid        (mst_bid),
    .mst_bresp      (mst_bresp)
    );

  // ---------------------
  // DMA Stream-to-Memory
  // ---------------------
  dma_mem2strm #(
    .StrmDataBits  (StrmDataBits),
    .MemDataBits   (MemDataBits),
    .AddrBits      (AddrBits),
    .LengthBits    (LengthBits),
    .FifoDepth     (FifoDepth))
  dma_rd (
    .clk            (clk),
    .rst            (rst),
    //
    .cfg_paddr      (rcfg_paddr),
    .cfg_pwrite     (rcfg_pwrite),
    .cfg_pwdata     (rcfg_pwdata),
    .cfg_psel       (rcfg_psel),
    .cfg_penable    (rcfg_penable),
    .cfg_pready     (rcfg_pready),
    .cfg_prdata     (rcfg_prdata),
    .cfg_pslverr    (rcfg_pslverr),
    .cfg_irq        (rcfg_irq),
    //
    .dout_valid     (dout_valid),
    .dout_ready     (dout_ready),
    .dout_data      (dout_data),
    .dout_eof       (dout_eof),
    //
    .mst_arvalid    (mst_arvalid),
    .mst_arready    (mst_arready),
    .mst_arid       (mst_arid),
    .mst_araddr     (mst_araddr),
    .mst_arlen      (mst_arlen),
    .mst_arsize     (mst_arsize),
    .mst_arlock     (mst_arlock),
    .mst_arburst    (mst_arburst),
    //
    .mst_rvalid     (mst_rvalid),
    .mst_rready     (mst_rready),
    .mst_rid        (mst_rid),
    .mst_rdata      (mst_rdata),
    .mst_rresp      (mst_rresp),
    .mst_rlast      (mst_rlast)
    );

endmodule

