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
// DMA Memory to Stream (AXI3)
// -----------------------------------------------------------------------------
// Reads data from memory over an AXI interface and outputs this as a stream.
// Memory words are optionally serialized into smaller outgoing stream words.
// DMA transactions are configured via an APB interface.
//
// See dma_cfg.v for configuration register details.
//
// NOTE: DMA transfers must be an integer number of memory words.
//       There is currently no byte-enable (strobe) support.
//
// -----------------------------------------------------------------------------
module dma_mem2strm #(
  parameter StrmDataBits  = 8,
  parameter MemDataBits   = 64,
  parameter AddrBits      = 32, // can this be changed for axi interconnect?
  parameter LengthBits    = 16, // bits for length of DMA transfer (in words)
  parameter FifoDepth     = 64)
(
  input                     clk,
  input                     rst,
  // APB Interface for Config
  input [5:0]               cfg_paddr,   // byte address
  input                     cfg_psel,
  input                     cfg_penable,
  input                     cfg_pwrite,
  input [31:0]              cfg_pwdata,
  output                    cfg_pready,
  output [31:0]             cfg_prdata,
  output                    cfg_pslverr,
  output                    cfg_irq,
  // Output Data Stream
  output                    dout_valid,
  input                     dout_ready,
  output [StrmDataBits-1:0] dout_data,
  output                    dout_eof,
  // Read Address Channel
  output                    mst_arvalid,
  input                     mst_arready,
  output [3:0]              mst_arid, // needed?
  output [31:0]             mst_araddr,
  output [3:0]              mst_arlen,
  output [2:0]              mst_arsize, // needed?
  output [1:0]              mst_arburst,
  output [1:0]              mst_arlock, // needed?
  // Read Data Channel
  input                     mst_rvalid,
  output                    mst_rready,
  input [3:0]               mst_rid,
  input [MemDataBits-1:0]   mst_rdata,
  input [1:0]               mst_rresp,
  input                     mst_rlast);

`include "util.vh"

  localparam BurstBits = 5; // size of max burst supported by axi3 is 16
  localparam FifoUsedBits = clog2(FifoDepth+1);

  // ---------------------------
  // APB Interface & Config Regs
  // ---------------------------
  wire [AddrBits-1:0]     cfg_source;
  wire [LengthBits-1:0]   cfg_len;
  wire [4:0]              cfg_burst;
  wire                    cfg_valid;
  wire                    cfg_busy;
  wire                    cfg_done;
  wire [LengthBits-1:0]   cfg_remain;
  wire [1:0]              cfg_err;
  wire [9:0]              cfg_status;

  wire [FifoUsedBits-1:0] fifo_used, fifo_free;

  dma_cfg #(
    .AddrBits     (AddrBits),
    .LengthBits   (LengthBits),
    .BurstBits    (BurstBits),
    .FifoUsedBits (FifoUsedBits))
  cfg(
    .clk           (clk),
    .rst           (rst),
    //
    .cfg_paddr     (cfg_paddr),
    .cfg_psel      (cfg_psel),
    .cfg_penable   (cfg_penable),
    .cfg_pwrite    (cfg_pwrite),
    .cfg_pwdata    (cfg_pwdata),
    .cfg_pready    (cfg_pready),
    .cfg_prdata    (cfg_prdata),
    .cfg_pslverr   (cfg_pslverr),
    .cfg_irq       (cfg_irq),
    //
    .dma_start     (cfg_source),
    .dma_len       (cfg_len),
    .dma_burst     (cfg_burst),
    .dma_valid     (cfg_valid),
    .dma_done      (cfg_done),
    .dma_remain    (cfg_remain),
    .dma_fifo_used (fifo_used),
    .dma_status    (cfg_status),
    .dma_err       (cfg_err),
    .dma_curr_len  (cfg_len)
    );

  // status / debug signals
  assign cfg_status = {1'b0, 1'b0,       cfg_busy,   mst_arvalid, mst_arready,
                             mst_rvalid, mst_rready, dout_valid,  dout_ready};

  // ----------
  // DMA Reader
  // ----------
  wire                    rdr_valid, rdr_ready, rdr_eof;
  wire [MemDataBits-1:0]  rdr_data;
  dma_reader #(
    .DataBits      (MemDataBits),
    .AddrBits      (AddrBits),
    .LengthBits    (LengthBits),
    .FifoUsedBits  (FifoUsedBits))
  reader (
    .clk              (clk),
    .rst              (rst),
    //
    .cfg_source       (cfg_source),
    .cfg_len          (cfg_len),
    .cfg_burst        (cfg_burst),
    .cfg_valid        (cfg_valid),
    .cfg_busy         (cfg_busy),
    .cfg_done         (cfg_done),
    .cfg_remain       (cfg_remain),
    .cfg_err          (cfg_err),
    //
    .dout_valid       (rdr_valid),
    .dout_ready       (rdr_ready),
    .dout_data        (rdr_data),
    .dout_eof         (rdr_eof),
    .dout_fifo_free   (fifo_free),
    //
    .mst_arvalid      (mst_arvalid),
    .mst_arready      (mst_arready),
    .mst_arid         (mst_arid),
    .mst_araddr       (mst_araddr),
    .mst_arlen        (mst_arlen),
    .mst_arsize       (mst_arsize),
    .mst_arlock       (mst_arlock),
    .mst_arburst      (mst_arburst),
    //
    .mst_rvalid       (mst_rvalid),
    .mst_rready       (mst_rready),
    .mst_rid          (mst_rid),
    .mst_rdata        (mst_rdata),
    .mst_rresp        (mst_rresp),
    .mst_rlast        (mst_rlast)
    );

  // ----
  // Fifo
  // ----
  wire                    fifo_valid, fifo_ready, fifo_eof;
  wire [MemDataBits-1:0]  fifo_data;
  stream_fifo_1clk #(
    .Width    (MemDataBits+1),
    .Depth    (FifoDepth))
  fifo(
    .rst       (rst),
    .clk       (clk),
    //
    .din_valid (rdr_valid),
    .din_ready (rdr_ready),
    .din_data  ({rdr_eof, rdr_data}),
    //
    .dout_valid(fifo_valid),
    .dout_ready(fifo_ready),
    .dout_data ({fifo_eof, fifo_data}),
    .used      (fifo_used));

  assign fifo_free = FifoDepth - fifo_used;

  // ----------
  // Serializer
  // ----------
  generate
    if (StrmDataBits < MemDataBits) begin: use_ser
      stream_serializer_eof #(
        .DataBits (StrmDataBits),
        .Ratio    (MemDataBits / StrmDataBits))
      ser (
        .rst       (rst),
        .clk       (clk),
        .in_valid  (fifo_valid),
        .in_ready  (fifo_ready),
        .in_data   (fifo_data),
        .in_eof    (fifo_eof),
        .out_valid (dout_valid),
        .out_ready (dout_ready),
        .out_data  (dout_data),
        .out_eof   (dout_eof));

    end else begin: no_ser
      assign dout_valid  = fifo_valid;
      assign dout_data   = fifo_data;
      assign dout_eof    = fifo_eof;
      assign fifo_ready  = dout_ready;
    end
  endgenerate

endmodule
