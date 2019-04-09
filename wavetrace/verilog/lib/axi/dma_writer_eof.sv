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
// AXI Dma Writer with end-of-frame input
// -----------------------------------------------------------------------------
// This module transfers frames of data from a stream to a memory over an AXI
// interface. An address channel provides the starting address for each frame.
// Frame data is written continuously until the end-of-frame signal is received.
//
// AXI bursts are only issued when the internal fifo holds enough data to
// complete the burst. The EOF flag is used to determine the length of the
// the final burst in the frame.
//
// The 'done' output pulses high when the final word of a frame has been
// sampled by the AXI interface.
//
// NOTE: All starting addresses must be memory word aligned.
//
// -----------------------------------------------------------------------------
module dma_writer_eof #(
  parameter DataBits      = 64,  // must be power of two
  parameter AddrBits      = 32,
  parameter BurstSize     = 16,  // AXI burst size
  parameter FifoDepth     = 32)  // Depth of fifo, must be >= BurstSize
(
  input                       clk,
  input                       rst,
  // Input Data Stream
  input                       din_valid,
  output                      din_ready,
  input [DataBits-1:0]        din_data,
  input                       din_eof,
  // Input Address Stream
  input                       cfg_valid,
  output                      cfg_ready,
  input [AddrBits-1:0]        cfg_addr,  // byte address, must be word aligned
  // Write Address Channel
  output logic                mst_awvalid,
  input                       mst_awready,
  output [3:0]                mst_awid,  // tied low for all transactions
  output logic [AddrBits-1:0] mst_awaddr,
  output logic [3:0]          mst_awlen,
  output [2:0]                mst_awsize,
  output [1:0]                mst_awburst, // tied to '01' for increment
  output [1:0]                mst_awlock,  // tied to '00' for non-locked access
  // Write Data Channel
  output                      mst_wvalid,
  input                       mst_wready,
  output [3:0]                mst_wid,    // tied low for all transactions
  output [DataBits/8-1:0]     mst_wstrb,  // byte-enable, all bits tied high
  output                      mst_wlast,
  output [DataBits-1:0]       mst_wdata,
  // Write Response Channel
  input                       mst_bvalid,
  output                      mst_bready,
  input [3:0]                 mst_bid,
  input [1:0]                 mst_bresp,
  //
  output logic                done,    // pulses high at end of transfer
  output logic [1:0]          error);  // last error code seen on bresp channel

`include "util.vh"

  localparam BurstBits = $clog2(BurstSize + 1);
  localparam BytesPerWord = DataBits / 8;

  // -----------------
  // Split Data Stream
  // -----------------
  // Split the data stream between the fifo and end-of-frame buffer
  logic [1:0] split_valid, split_ready;
  stream_split split (
    .in_valid  (din_valid),
    .in_ready  (din_ready),
    .out_valid (split_valid),
    .out_ready (split_ready));

  // ---------
  // Data Fifo
  // ---------
  // AXI bursts are only issued when this fifo contains enough data to
  // actually complete the burst.
  logic                           fifo_valid, fifo_ready, fifo_eof;
  logic [DataBits-1:0]            fifo_data;
  logic [$clog2(FifoDepth+1)-1:0] fifo_used;

  stream_fifo_1clk #(
    .Width (DataBits + 1),
    .Depth (FifoDepth))
  fifo (
    .clk        (clk),
    .rst        (rst),
    //
    .din_valid  (split_valid[0]),
    .din_ready  (split_ready[0]),
    .din_data   ({din_eof, din_data}),
    //
    .dout_valid (fifo_valid),
    .dout_ready (fifo_ready),
    .dout_data  ({fifo_eof, fifo_data}),
    .used       (fifo_used));

  // ----------
  // EOF Buffer
  // ----------
  // This is used to indicate when the fifo contains the EOF word. We only
  // want a one-deep buffer here so that we backpressure after receiving EOF,
  // allowing the final burst size to be calculated using the 'fifo_used' count,
  // and ensuring the fifo never contains data from two different frames.
  logic eof_valid, eof_ready;
  stream_buf_v #(
    .DataBits (1))
  lbuf (
    .clk       (clk),
    .rst       (rst),
    .in_valid  (split_valid[1] & din_eof),
    .in_ready  (split_ready[1]),
    .in_data   (1'b0),
    .out_valid (eof_valid),
    .out_ready (eof_ready),
    .out_data  ( ));  // unused, we just use the eof_valid signal directly

  // --------------------------
  // Transaction State Machine
  // --------------------------
  logic                 mst_wvalid_i, mst_wready_i, mst_wlast_i;
  logic [DataBits-1:0]  mst_wdata_i;
  logic [BurstBits-1:0] burst_remain;
  logic [AddrBits-1:0]  next_addr;
  logic [9:0]           until_4k;
  logic                 final_burst;

  enum {Idle, PrepBurst1, PrepBurst2, WaitFifo,
        IssueBurst, DoBurst, WaitFinal} state;

  always_ff @(posedge clk) begin

    // Default register values
    eof_ready <= '0;
    done      <= '0;

    // By default, clear the awvalid register when the channel is sampled
    if (mst_awready) begin
      mst_awvalid <= '0;
    end

    case (state)
      // -----------------------------------------------------------
      Idle:
        if (cfg_valid) begin
          next_addr   <= cfg_addr;
          final_burst <= '0;
          state       <= PrepBurst1;
        end
      // -----------------------------------------------------------
      PrepBurst1:
        begin
          // Per AXI spec, bursts must not cross 4K boundaries
          until_4k <= (13'h1000 - next_addr[11:0]) / BytesPerWord;
          state    <= PrepBurst2;
        end
      // -----------------------------------------------------------
      PrepBurst2:
        begin
          burst_remain <= min(BurstSize, until_4k);
          state        <= WaitFifo;
        end
      // -----------------------------------------------------------
      WaitFifo:
        begin
          // If the fifo contains an EOF and is holding the burst size, or less,
          // we're on the final burst for this frame. In this case, we may need
          // to issue a reduced size burst to complete the frame.
          if (eof_valid && (fifo_used <= burst_remain)) begin
            eof_ready    <= '1;
            final_burst  <= '1;
            burst_remain <= fifo_used;
            state        <= IssueBurst;
          end else if (fifo_used >= burst_remain) begin
            state <= IssueBurst;
          end
        end
      // -----------------------------------------------------------
      IssueBurst:
        if (!mst_awvalid || mst_awready) begin
          mst_awvalid <= '1;
          mst_awlen   <= burst_remain - 1; // for AXI, arlen = burst_size - 1
          mst_awaddr  <= next_addr;
          next_addr   <= next_addr + (burst_remain * BytesPerWord);
          state       <= DoBurst;
        end
      // -----------------------------------------------------------
      DoBurst:
        if (mst_wready_i && mst_wvalid_i) begin
          burst_remain <= burst_remain - 1;
          if (burst_remain == 1)
            state <= (final_burst) ? WaitFinal : PrepBurst1;
        end
      // -----------------------------------------------------------
      WaitFinal:
        // Wait for output buffer to clear to avoid issuing done pulse too early
        if (!mst_wvalid) begin
          done  <= '1;
          state <= Idle;
        end
    endcase

    // Monitor response channel for errors
    if (mst_bvalid && mst_bready) begin
      error <= mst_bresp;
    end

    if (rst) begin
      state        <= Idle;
      mst_awvalid  <= '0;
      done         <= '0;
      error        <= '0;
      eof_ready    <= '0;
    end
  end

  assign cfg_ready = (state == Idle);

  // Pass the data stream to the write-data channel when doing a burst
  assign mst_wvalid_i  = (state == DoBurst) ? fifo_valid   : 0;
  assign fifo_ready    = (state == DoBurst) ? mst_wready_i : 0;
  assign mst_wdata_i   = fifo_data;
  assign mst_wlast_i   = (burst_remain == 1) ? 1 : 0;

  // Register everything going out on the write channel
  stream_buf_v #(
    .DataBits(DataBits+1))
  obuf (
    .clk       (clk),
    .rst       (rst),
    .in_valid  (mst_wvalid_i),
    .in_ready  (mst_wready_i),
    .in_data   ({mst_wlast_i, mst_wdata_i}),
    .out_valid (mst_wvalid),
    .out_ready (mst_wready),
    .out_data  ({mst_wlast, mst_wdata}));

  // We're always ready for the response channel
  assign mst_bready = 1'b1;

  // Other AXI signals we need to drive
  assign mst_awid    = 4'b0;
  assign mst_awsize  = clog2(BytesPerWord);
  assign mst_awlock  = 2'b00;
  assign mst_awburst = 2'b01;
  assign mst_wid     = 4'b0;
  assign mst_wstrb   = '1;  // all ones

endmodule
