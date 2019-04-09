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
// Dma Stream To Memory
// -----------------------------------------------------------------------------
// Writes a stream of data to memory via an AXI interface. Incoming data is
// deserialized into memory size words. DMA transactions are configured via an
// APB interface.
//
// See dma_cfg.v for configuration register details.
//
// NOTE: DMA transfers must be an integer number of memory words.
//       There is currently no byte-enable (strobe) support.
//
// -----------------------------------------------------------------------------
module dma_strm2mem #(
  parameter StrmDataBits = 8,
  parameter MemDataBits  = 64,
  parameter AddrBits     = 32,
  parameter LengthBits   = 16,
  parameter FifoDepth    = 64,
  parameter LenInStrm    = 0)  // extracts the dma length from the front of the
                               //   data stream
(
  input                      clk,
  input                      rst,
  // APB Interface for Config
  input [5:0]                cfg_paddr, // byte address
  input                      cfg_psel,
  input                      cfg_penable,
  input                      cfg_pwrite,
  input [31:0]               cfg_pwdata,
  output                     cfg_pready,
  output [31:0]              cfg_prdata,
  output                     cfg_pslverr,
  output                     cfg_irq,
  // Input Data Stream
  input                      din_valid,
  output                     din_ready,
  input [StrmDataBits-1:0]   din_data,
  input                      din_eof,
  // Write Address Channel
  output                     mst_awvalid,
  input                      mst_awready,
  output [3:0]               mst_awid, // tied low for all transactions
  output [AddrBits-1:0]      mst_awaddr,
  output [3:0]               mst_awlen, // number of words in each burst 0=1, 15=16
  output [2:0]               mst_awsize, // number of bytes in each data word '11' for 8
  output [1:0]               mst_awburst, // tied to '01' for increment
  output [1:0]               mst_awlock, // tied to '00' for normal non-locked access
  // Write Data Channel
  output                     mst_wvalid,
  input                      mst_wready,
  output [3:0]               mst_wid, // tied low for all transactions
  output [MemDataBits/8-1:0] mst_wstrb, // byte enable, tied high
  output                     mst_wlast, // high at end of each burst
  output [MemDataBits-1:0]   mst_wdata,
  // Write Response Channel
  input                      mst_bvalid,
  output                     mst_bready,
  input [3:0]                mst_bid,
  input [1:0]                mst_bresp);

`include "util.vh"

  localparam BurstBits    = 5; // size of max burst supported by axi3 is 16
  localparam FifoUsedBits = clog2(FifoDepth+1);

  // ----------------------------
  // APB Interface & Config Regs
  // ----------------------------
  wire [AddrBits-1:0]     cfg_dest;
  wire [LengthBits-1:0]   cfg_len;
  wire [4:0]              cfg_burst;
  wire                    cfg_valid;
  wire                    cfg_busy;
  wire                    cfg_done;
  wire [LengthBits-1:0]   cfg_remain;
  wire [1:0]              cfg_err;
  wire [9:0]              cfg_status;

  wire                    fifo_valid, fifo_ready;
  wire [MemDataBits-1:0]  fifo_data;
  wire [FifoUsedBits-1:0] fifo_used;

  wire [LengthBits-1:0]   len_buf_data;

  dma_cfg #(
    .AddrBits      (AddrBits),
    .LengthBits    (LengthBits),
    .BurstBits     (BurstBits),
    .FifoUsedBits  (FifoUsedBits))
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
    .dma_start     (cfg_dest),
    .dma_len       (cfg_len),
    .dma_burst     (cfg_burst),
    .dma_valid     (cfg_valid),
    .dma_done      (cfg_done),
    .dma_remain    (cfg_remain),
    .dma_fifo_used (fifo_used),
    .dma_status    (cfg_status),
    .dma_err       (cfg_err),
    .dma_curr_len  (len_buf_data)
    );

  // status / debug signals
  assign cfg_status = {                                        cfg_busy,
                       mst_awvalid, mst_awready, mst_wvalid, mst_wready,
                       mst_bvalid,  mst_bready,  din_valid,  din_ready};

  // ------------
  // Deserializer
  // ------------
  wire                   dser_valid, dser_ready, dser_eof;
  wire [MemDataBits-1:0] dser_data;
  generate
    if (StrmDataBits < MemDataBits) begin: use_deser
      stream_deserializer_eof #(
        .DataBits (StrmDataBits),
        .Ratio    (MemDataBits / StrmDataBits))
      dser (
        .rst       (rst),
        .clk       (clk),
        .in_valid  (din_valid),
        .in_ready  (din_ready),
        .in_data   (din_data),
        .in_eof    (din_eof),
        .out_valid (dser_valid),
        .out_ready (dser_ready),
        .out_data  (dser_data),
        .out_eof   (dser_eof));

    end else begin: no_deser
      assign dser_valid  = din_valid;
      assign dser_data   = din_data;
      assign dser_eof    = din_eof;
      assign din_ready   = dser_ready;
    end
  endgenerate

  // --------------------------
  // Extract Length from Stream
  // --------------------------
  wire [1:0] split_valid, split_ready;
  wire       cfg_mrg_valid;

  generate if (LenInStrm) begin :get_len

    // generate a 'start-of-frame' signal
    reg dser_sof;
    always @(posedge clk) begin
      if (dser_valid & dser_ready)
        dser_sof <= dser_eof;
      if (rst)
        dser_sof <= 1;
    end

    // split off the stream for the length extraction
    stream_split split(
      .in_valid  (dser_valid),
      .in_ready  (dser_ready),
      .out_valid (split_valid),
      .out_ready (split_ready));

    // get length from the start of the frame and convert to words
    wire [LengthBits-1:0] len_data  = dser_data[15:0] >> clog2(MemDataBits/8);
    wire                  len_valid = split_valid[1] & dser_sof;

    // double buffer the length so we don't introduce any stalls in the pipeline
    wire        len_buf_valid;
    stream_fifo_1clk_regs #(
      .Width (LengthBits),
      .Depth (2))
    len_buf(
      .clk       (clk),
      .rst       (rst),
      .din_valid (len_valid),
      .din_ready (split_ready[1]),
      .din_data  (len_data),
      .dout_valid(len_buf_valid),
      .dout_ready(cfg_done),
      .dout_data (len_buf_data),
      .used      ());

    // proceed when we have a valid length and a valid set of config registers
    assign cfg_mrg_valid = cfg_valid & len_buf_valid;

  end else begin :no_len
    assign split_valid[0] = dser_valid;
    assign dser_ready     = split_ready[0];
    assign cfg_mrg_valid  = cfg_valid;
    assign len_buf_data   = cfg_len;
  end endgenerate

  // ----
  // Fifo
  // ----
  stream_fifo_1clk #(
    .Width    (MemDataBits),
    .Depth    (FifoDepth))
  fifo(
    .rst       (rst),
    .clk       (clk),
    //
    .din_valid (split_valid[0]),
    .din_ready (split_ready[0]),
    .din_data  (dser_data),
    //
    .dout_valid(fifo_valid),
    .dout_ready(fifo_ready),
    .dout_data (fifo_data),
    .used      (fifo_used));

  // ----------
  // Dma Writer
  // ----------
  dma_writer #(
    .DataBits      (MemDataBits),
    .AddrBits      (AddrBits),
    .LengthBits    (LengthBits),
    .FifoUsedBits  (FifoUsedBits))
  writer(
    .clk              (clk),
    .rst              (rst),
    //
    .cfg_dest         (cfg_dest),
    .cfg_len          (len_buf_data),
    .cfg_burst        (cfg_burst),
    .cfg_valid        (cfg_mrg_valid),
    .cfg_busy         (cfg_busy),
    .cfg_done         (cfg_done),
    .cfg_remain       (cfg_remain),
    .cfg_err          (cfg_err),
    //
    .din_valid        (fifo_valid),
    .din_ready        (fifo_ready),
    .din_data         (fifo_data),
    .din_fifo_used    (fifo_used),
    //
    .mst_awvalid      (mst_awvalid),
    .mst_awready      (mst_awready),
    .mst_awid         (mst_awid),
    .mst_awaddr       (mst_awaddr),
    .mst_awlen        (mst_awlen),
    .mst_awsize       (mst_awsize),
    .mst_awlock       (mst_awlock),
    .mst_awburst      (mst_awburst),
    //
    .mst_wvalid       (mst_wvalid),
    .mst_wready       (mst_wready),
    .mst_wid          (mst_wid),
    .mst_wstrb        (mst_wstrb),
    .mst_wlast        (mst_wlast),
    .mst_wdata        (mst_wdata),
    //
    .mst_bvalid       (mst_bvalid),
    .mst_bready       (mst_bready),
    .mst_bid          (mst_bid),
    .mst_bresp        (mst_bresp));

endmodule
