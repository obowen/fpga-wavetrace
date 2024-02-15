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
// Dma Writer (AXI3)
// -----------------------------------------------------------------------------
// Performs a memory mapped transfer from an incoming data stream over an
// AXI interface. The transfer will start when cfg_go is high. The transfer
// will be repeated if cfg_go is held high.
//
// NOTE: All transfers must be memory word aligned
//
// -----------------------------------------------------------------------------
module dma_writer #(
  parameter DataBits      = 64,
  parameter AddrBits      = 32,
  parameter LengthBits    = 16,
  parameter FifoUsedBits  = 7)
(
  input                     clk,
  input                     rst,
  // Configuration Interface
  input [AddrBits-1:0]      cfg_dest,  // destination address for transfer
  input [LengthBits-1:0]    cfg_len,   // length of transfer in 64-bit words
  input [4:0]               cfg_burst, // max burst size for transfer (AXI supports up to 16)
  input                     cfg_valid, // indicates cfg is valid and starts transfer
  output                    cfg_busy,  // high when transfer is underway
  output reg                cfg_done,  // pulses high on final word of transfer
  output [LengthBits-1:0]   cfg_remain,// number of words remaining in transfer
  output reg [1:0]          cfg_err,   // AXI error code seen on write response channel
  // Input Data Stream
  input                     din_valid,
  output                    din_ready,
  input [DataBits-1:0]      din_data,
  input [FifoUsedBits-1:0]  din_fifo_used, // writes issued when fifo contains a burst of data
  // Write Address Channel
  output reg                mst_awvalid,
  input                     mst_awready,
  output [3:0]              mst_awid,    // tied low for all trasactions
  output reg [AddrBits-1:0] mst_awaddr,
  output reg [3:0]          mst_awlen,   // number of words in each burst 0=1, 15=16
  output [2:0]              mst_awsize,  // number of bytes in each data word '11' for 8
  output [1:0]              mst_awburst, // set to '01' for increment
  output [1:0]              mst_awlock,  // needed ? set to '00' for normal non-locked access
  // Write Data Channel
  output                    mst_wvalid,
  input                     mst_wready,
  output [3:0]              mst_wid,     // tied low for all transactions
  output [DataBits/8-1:0]   mst_wstrb,   // byte-enable, tied high
  output                    mst_wlast,   // high at end of each burst
  output [DataBits-1:0]     mst_wdata,
  // Write Response Channel
  input                     mst_bvalid,
  output                    mst_bready,
  input [3:0]               mst_bid,
  input [1:0]               mst_bresp);

`include "util.vh"

  localparam BurstBits = 5;
  localparam BytesPerWord = DataBits / 8;

  wire                mst_wvalid_i;
  wire                mst_wready_i;
  wire                mst_wlast_i;
  wire [DataBits-1:0] mst_wdata_i;

  // --------------------------
  // Transaction State Machine
  // --------------------------
  localparam Idle        = 0,
             PrepBurst1  = 1,
             PrepBurst2  = 2,
             WaitFifo    = 3,
             DoBurst     = 4,
             WaitFinal   = 5,
             Done        = 6,
             NumStates   = 7;

  reg [clog2(NumStates)-1:0] state;
  reg [BurstBits-1:0]        burst_remain, burst_cand;
  reg [LengthBits-1:0]       total_remain;
  reg [AddrBits-1:0]         next_addr;
  reg [10:0]                 until_4k;
  always @(posedge clk) begin

    // default behavior
    if (mst_awready) begin
      mst_awvalid <= 0;
    end

    case (state)
      // -------------------------------------------------
      Idle:
        if (cfg_valid) begin
          if (cfg_len >=1 ) begin
            total_remain <= cfg_len;
            next_addr    <= cfg_dest;
            state        <= PrepBurst1;
          end else begin
            cfg_done <= 1;
            state    <= Done;
          end
        end
      // -------------------------------------------------
      PrepBurst1:
        begin
          burst_cand <= min(total_remain, cfg_burst);
          until_4k   <= (13'h1000 - next_addr[11:0]) / BytesPerWord;
          state      <= PrepBurst2;
        end
      // -------------------------------------------------
      PrepBurst2:
        begin
          // do not allow burst to cross 4K memory boundary as per AXI spec
          burst_remain <= min(burst_cand, until_4k);
          state        <= WaitFifo;
        end
      // -------------------------------------------------
      WaitFifo:
        if (din_fifo_used >= burst_remain) begin
          if (!mst_awvalid || mst_awready) begin
            mst_awvalid <= 1;
            mst_awlen   <= burst_remain - 1; // for AXI, arlen = burst_size - 1
            mst_awaddr  <= next_addr;
            next_addr   <= next_addr + (burst_remain * BytesPerWord);
            state       <= DoBurst;
          end
        end
      // -------------------------------------------------
      DoBurst:
        if (mst_wready_i && mst_wvalid_i) begin
          burst_remain <= burst_remain - 1;
          total_remain <= total_remain - 1;
          if (total_remain == 1) begin
            state <= WaitFinal;
          end else if (burst_remain == 1) begin
            state <= PrepBurst1;
          end
        end
      // -------------------------------------------------
      WaitFinal:
        // wait for output buffer to clear to avoid issuing irq too early
        if (!mst_wvalid) begin
          cfg_done <= 1;
          state    <= Done;
        end
      // -------------------------------------------------
      Done:
        begin
          // this state gives cfg_valid a chance to react to cfg_done pulse
          cfg_done <= 0;
          state    <= Idle;
        end
    endcase

    // monitor response channel for errors
    if (mst_bvalid && mst_bready) begin
      cfg_err <= mst_bresp;
    end

    if (rst) begin
      state        <= Idle;
      mst_awvalid  <= 0;
      cfg_done     <= 0;
      cfg_err      <= 0;
      total_remain <= 0;
    end

  end

  assign cfg_busy    = (state != Idle);
  assign cfg_remain  = total_remain;

  // pass the data stream to the write-data channel when doing a burst
  assign mst_wvalid_i  = (state == DoBurst) ? din_valid    : 0;
  assign din_ready     = (state == DoBurst) ? mst_wready_i : 0;
  assign mst_wdata_i   = din_data;
  assign mst_wlast_i   = (burst_remain == 1) ? 1 : 0;

  // register everything going out on the write channel
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

  // always ready for response channel
  assign mst_bready  = 1'b1;

  // other AXI signals we need to drive
  assign mst_awid    = 4'b0;
  assign mst_awsize  = clog2(BytesPerWord);
  assign mst_awlock  = 2'b00;
  assign mst_awburst = 2'b01;
  assign mst_wid     = 4'b0;
  assign mst_wstrb   = {DataBits/8{1'b1}};

endmodule
