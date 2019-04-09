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
// Dma Reader (AXI3)
// -----------------------------------------------------------------------------
// Reads data from memory over an AXI interface and outputs this as a data
// stream. Details of the DMA transaction are provided on the 'cfg' interface.
//
// -----------------------------------------------------------------------------
module dma_reader #(
  parameter DataBits      = 64,
  parameter AddrBits      = 32, // size of address bus
  parameter LengthBits    = 16, // bits for length of DMA transfer (in words)
  parameter BurstBits     =  5, // bits for the transfer burst size
  parameter FifoUsedBits  = 10) // bits for fifo_free port
(
  input                     clk,
  input                     rst,
  // Configuration Interface
  input [AddrBits-1:0]      cfg_source,  // source address for transfer
  input [LengthBits-1:0]    cfg_len,     // length of transfer in 64-bit words
  input [BurstBits-1:0]     cfg_burst,   // max burst size for (AXI supports up to 16)
  input                     cfg_valid,   // indicates cfg is valid and starts transfer
  output                    cfg_busy,    // high when transfer is underway
  output reg                cfg_done,    // pulses high on final word of transfer
  output [LengthBits-1:0]   cfg_remain,  // number of words remaining in transfer
  output reg [1:0]          cfg_err,     // AXI error code seen in the read response
  // Output Data Stream
  output                    dout_valid,
  input                     dout_ready,
  output [DataBits-1:0]     dout_data,
  output                    dout_eof,
  input  [FifoUsedBits-1:0] dout_fifo_free, // reads only issued when there is space in fifo
  // Read Address Channel
  output reg                mst_arvalid,
  input                     mst_arready,
  output reg [AddrBits-1:0] mst_araddr,
  output reg [3:0]          mst_arlen,
  output [3:0]              mst_arid,
  output [2:0]              mst_arsize,
  output [1:0]              mst_arburst,
  output [1:0]              mst_arlock,
  // Read Data Channel
  input                     mst_rvalid,
  output                    mst_rready,
  input [3:0]               mst_rid,
  input [DataBits-1:0]      mst_rdata,
  input [1:0]               mst_rresp,
  input                     mst_rlast);

`include "util.vh"

  localparam BytesPerWord = DataBits / 8;

  // --------------------------
  // Transaction State Machine
  // --------------------------
  localparam Idle         = 0,
             PrepBurst1   = 1,
             PrepBurst2   = 2,
             PrepBurst3   = 3,
             IssueBurst   = 4,
             WaitPending  = 5,
             Done         = 6,
             NumStates    = 7;

  reg [clog2(NumStates)-1:0] state;
  reg [BurstBits-1:0]        burst_cand, next_burst;
  reg [LengthBits-1:0]       remain, pending;
  reg [9:0]                  until_4k;
  reg [AddrBits-1:0]         next_addr;
  reg [FifoUsedBits-1:0]     fifo_required;

  always @(posedge clk) begin:transacs
    reg [LengthBits-1:0] pending_i;

    // default behavior
    pending_i = pending;
    if (mst_arready) begin
      mst_arvalid <= 0;
    end

    case (state)
      // -------------------------------------------------------------
      Idle:
        if (cfg_valid) begin
          if (cfg_len >= 1) begin
            remain     <= cfg_len;
            next_addr  <= cfg_source;
            state      <= PrepBurst1;
          end else begin
            cfg_done <= 1;
            state    <= Done;
          end
        end
      // -------------------------------------------------------------
      PrepBurst1:
        begin
          if (remain > 0) begin
            burst_cand <= min(remain, cfg_burst);
            until_4k   <= (13'h1000 - next_addr[11:0]) / BytesPerWord;
            state      <= PrepBurst2;
          end else begin
            state <= WaitPending;
          end
        end
      // -------------------------------------------------------------
      PrepBurst2:
        begin
          // do not allow burst to cross 4K memory boundary as per AXI spec
          next_burst <= min(burst_cand, until_4k);
          state      <= PrepBurst3;
        end
      // -------------------------------------------------------------
      PrepBurst3:
        begin
          fifo_required <= pending_i + next_burst;
          state         <= IssueBurst;
        end
      // -------------------------------------------------------------
      IssueBurst:
        begin
          if (dout_fifo_free >= fifo_required) begin
            if (!mst_arvalid || mst_arready) begin
              mst_arvalid <= 1;
              mst_araddr  <= next_addr;
              mst_arlen   <= next_burst - 1; // for AXI, arlen = burst_size - 1
              pending_i    = pending_i + next_burst;
              remain      <= remain - next_burst;
              next_addr   <= next_addr + (next_burst * BytesPerWord);
              state       <= PrepBurst1;
            end
          end else begin
            fifo_required <= pending_i + next_burst;
          end
        end
      // -------------------------------------------------------------
      WaitPending:
        if (dout_valid & dout_ready & dout_eof) begin
          cfg_done <= 1;
          state    <= Done;
        end
      // -------------------------------------------------------------
      Done:
        begin
          // this state gives cfg_valid a chance to react to cfg_done pulse
          cfg_done <= 0;
          state    <= Idle;
        end
    endcase

    // track incoming read data and catch any bus errors
    if (mst_rvalid & mst_rready) begin
      if (pending_i > 0) begin // (just in case slave does something unexpected)
        pending_i = pending_i - 1;
      end
      cfg_err <= mst_rresp;
    end

    pending <= pending_i;

    if (rst) begin
      state       <= Idle;
      cfg_done    <= 0;
      cfg_err     <= 0;
      remain      <= 0;
      pending     <= 0;
      mst_arvalid <= 0;
    end

  end

  assign cfg_busy   = (state != Idle);
  assign cfg_remain = remain;

  // pass read-data channel directlty to output stream
  assign dout_valid = mst_rvalid;
  assign dout_data  = mst_rdata;
  assign dout_eof = (remain == 0 && pending == 1);
  assign mst_rready = dout_ready;

  assign mst_arid    = 4'b0;
  assign mst_arsize  = clog2(DataBits/8);
  assign mst_arlock  = 2'b00;
  assign mst_arburst = 2'b01;

endmodule
