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
// AXI Dma Reader with end-of-frame output
// -----------------------------------------------------------------------------
// Reads data from memory over an AXI interface and outputs this as a data
// stream, along with an end-of-frame flag. A configuration interface stream
// provides the addresses and lengths for DMA transfers.
//
// This module uses an internal fifo to hold data read from memory. AXI Read
// bursts are only issued when there is sufficient space in the FIFO to hold
// them.
//
// -----------------------------------------------------------------------------
module dma_reader_eof #(
  parameter DataBits      = 64,  // must be a power of 2
  parameter AddrBits      = 32,  // size of address bus
  parameter LengthBits    = 16,  // bits for length of DMA transfer (in words)
  parameter BurstSize     = 16,  // AXI burst size
  parameter FifoDepth     = 128) // Depth of fifo, must be >= BurstSize, and
                                 // account for read latency over AXI
(
  input                       clk,
  input                       rst,
  // Configuration Interface
  input                       cfg_valid,
  output                      cfg_ready,
  input [AddrBits-1:0]        cfg_addr,  // byte address, must be word aligned
  input [LengthBits-1:0]      cfg_len,   // length of transfer, in words
  // Output Data Stream
  output                      dout_valid,
  input                       dout_ready,
  output [DataBits-1:0]       dout_data,
  output                      dout_eof,
  // Read Address Channel
  output logic                mst_arvalid,
  input                       mst_arready,
  output logic [AddrBits-1:0] mst_araddr,
  output logic [3:0]          mst_arlen,
  output [3:0]                mst_arid,
  output [2:0]                mst_arsize,
  output [1:0]                mst_arburst,
  output [1:0]                mst_arlock,
  // Read Data Channel
  input                       mst_rvalid,
  output                      mst_rready,
  input [3:0]                 mst_rid,
  input [DataBits-1:0]        mst_rdata,
  input [1:0]                 mst_rresp,
  input                       mst_rlast,
  //
  output logic                done,    // pulses high at end of transfer
  output logic [1:0]          error);  // last error code seen on 'mst_rresp'

`include "util.vh"

  localparam BytesPerWord = DataBits / 8;
  localparam BurstBits = $clog2(BurstSize + 1);
  localparam FifoUsedBits = $clog2(FifoDepth + 1);

  // -------------------------
  // Transaction State Machine
  // -------------------------
  enum {Idle, PrepBurst1, PrepBurst2, PrepBurst3,
       IssueBurst, WaitPending} state;

  logic [BurstBits-1:0]    burst_cand, next_burst;
  logic [LengthBits-1:0]   remain, pending;
  logic [9:0]              until_4k;
  logic [AddrBits-1:0]     next_addr;
  logic [FifoUsedBits-1:0] fifo_used, fifo_free, fifo_required;

  always_ff @(posedge clk) begin:transacs
    reg [LengthBits-1:0] pending_next;

    // Defaults
    pending_next = pending;  // non-registered local helper signal

    // By default, clear the arvalid register when the channel is sampled
    if (mst_arready) begin
      mst_arvalid <= 0;
    end

    case (state)
      // -------------------------------------------------------------
      Idle:
        if (cfg_valid & cfg_len >= 1) begin
          remain    <= cfg_len;
          next_addr <= cfg_addr;
          state     <= PrepBurst1;
        end
      // -------------------------------------------------------------
      PrepBurst1:
        begin
          if (remain > 0) begin
            burst_cand <= min(remain, BurstSize);
            until_4k   <= (13'h1000 - next_addr[11:0]) / BytesPerWord;
            state      <= PrepBurst2;
          end else begin
            state <= WaitPending;
          end
        end
      // -------------------------------------------------------------
      PrepBurst2:
        begin
          // Do not allow burst to cross 4K memory boundary as per AXI spec
          next_burst <= min(burst_cand, until_4k);
          state      <= PrepBurst3;
        end
      // -------------------------------------------------------------
      PrepBurst3:
        begin
          fifo_required <= pending + next_burst;
          state         <= IssueBurst;
        end
      // -------------------------------------------------------------
      IssueBurst:
        begin
          if (fifo_free >= fifo_required) begin
            if (!mst_arvalid || mst_arready) begin
              mst_arvalid <= 1;
              mst_araddr  <= next_addr;
              mst_arlen   <= next_burst - 1; // for AXI, arlen = burst_size - 1
              pending_next = pending + next_burst;  // may get decremented below
              remain      <= remain - next_burst;
              next_addr   <= next_addr + (next_burst * BytesPerWord);
              state       <= PrepBurst1;
            end
          end else begin
            fifo_required <= pending + next_burst;
          end
        end
      // -------------------------------------------------------------
      WaitPending:
        if (pending == 0) begin
          state    <= Idle;
        end
    endcase

    // Track incoming read data and catch any bus errors
    if (mst_rvalid & mst_rready) begin
      if (pending_next > 0) begin  // protection against unexpected behavior
        pending_next = pending_next - 1;  // may also get incremented above
      end
      error <= mst_rresp;
    end

    pending <= pending_next;

    if (rst) begin
      state       <= Idle;
      error       <= '0;
      pending     <= '0;
      mst_arvalid <= '0;
    end

  end

  wire eof = (remain == 0 && pending == 1);

  assign done = mst_rvalid & mst_rdata & eof;
  assign cfg_ready = (state == Idle);

  // ---------
  // Data Fifo
  // ---------
  // Read bursts are only issued when there is sufficient space in
  // this fifo to hold them.
  stream_fifo_1clk #(
    .Width      (DataBits + 1),
    .Depth      (FifoDepth))
  fifo(
    .rst        (rst),
    .clk        (clk),
    //
    .din_valid  (mst_rvalid),
    .din_ready  (mst_rready),
    .din_data   ({eof, mst_rdata}),
    //
    .dout_valid (dout_valid),
    .dout_ready (dout_ready),
    .dout_data  ({dout_eof, dout_data}),
    .used       (fifo_used));

  assign fifo_free = FifoDepth - fifo_used;

  // Drive some additional AXI signals
  assign mst_arid    = 4'b0;
  assign mst_arsize  = clog2(DataBits/8);
  assign mst_arlock  = 2'b00;
  assign mst_arburst = 2'b01;

endmodule
