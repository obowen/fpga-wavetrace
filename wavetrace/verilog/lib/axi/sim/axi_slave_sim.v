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
// ----------------------------------------------------------------------------------
// AXI Slave Simulation Model
// ----------------------------------------------------------------------------------
// Implements a simple AXI slave simulation module supporting pending / queued read
// instructions. Parameters control how frequently the write-channel is ready to
// accept data and how frequently the read-channel provides valid data. The memory
// can be initialized from a file, and the memory contents can be dumped to a file
// as needed.
//
// NOTE: This block does not support 'id' or 'lock' features, and only supports
// incrementing bursts.
//
// ----------------------------------------------------------------------------------
module axi_slave_sim #(
  parameter DataBits        = 64,
  parameter AxiAddrBits     = 32, // TODO: or is this always just 32?
  parameter MemAddrBits     = 12,
  parameter NumPendingReads = 4,
  parameter WrThroughput    = 63, // percentage of time the 'write data' channel is ready
  parameter RdThroughput    = 57, // percentage of time the 'read data' channel is valid
  parameter Seed            = 3,
  parameter MemInitFile     = "undefined",
  parameter MemDumpFile     = "memdump.dat")
(
  input                   clk,
  input                   rst,
  //
  input                   dump_memory, // writes memory to file when high
  // Write Address Channel
  input                   slv_awvalid,
  output                  slv_awready,
  input [3:0]             slv_awid,    // *IGNORED*
  input [AxiAddrBits-1:0] slv_awaddr,  // write address (byte address)
  input [3:0]             slv_awlen,   // number of words in each burst 0=1, 15=16
  input [2:0]             slv_awsize,  // *IGNORED*
  input [1:0]             slv_awlock,  // *IGNORED*
  input [1:0]             slv_awburst, // *ONLY '01' SUPPORTED* (for increment mode)
  // Write Data Channel
  input                   slv_wvalid,
  output                  slv_wready,
  input [3:0]             slv_wid,     // *IGNORED*
  input [DataBits/8-1:0]  slv_wstrb,   // *TODO* bit vector to byte-enable part of wdata
  input                   slv_wlast,   // must be high at end of each burst
  input [DataBits-1:0]    slv_wdata,   // write data
  // Write Response Channel
  output reg              slv_bvalid,
  input                   slv_bready,
  output [3:0]            slv_bid,     // tied low
  output [1:0]            slv_bresp,   // tied low
  // Read Address Channel
  input                   slv_arvalid,
  output                  slv_arready,
  input [3:0]             slv_arid,
  input [AxiAddrBits-1:0] slv_araddr,  // byte address
  input [3:0]             slv_arlen,
  input [2:0]             slv_arsize,
  input [1:0]             slv_arlock,
  input [1:0]             slv_arburst,
  // Read Data Channel
  output                  slv_rvalid,
  input                   slv_rready,
  output [3:0]            slv_rid,     // *ALWAYS ZERO*
  output [DataBits-1:0]   slv_rdata,
  output [1:0]            slv_rresp,   // tied low
  output                  slv_rlast);

`include "util.vh"

  localparam ByteAddrBits = clog2(DataBits/8);

  // seed for random number gen
  integer seed_i;
  initial seed_i = Seed;

  // helper function to randomly return '1' or '0' with a given probability percentage
  function weighted_rand(input integer probability_of_one);
    integer rnd;
    begin
      rnd = $unsigned($random(seed_i)) % 100;
      weighted_rand = (rnd < probability_of_one) ? 1 : 0;
    end
  endfunction

  reg [DataBits-1:0]    memory[2**MemAddrBits-1:0];
  initial begin
    if (MemInitFile != "undefined")
      $readmemh(MemInitFile, memory);
  end

  always @(posedge dump_memory) begin
    $writememh(MemDumpFile, memory);
  end

  // --------------------
  // Write State Machine
  // --------------------
  localparam WrIdle = 0,
             WrBurst = 1;

  reg [1:0]             wr_state;
  reg [MemAddrBits-1:0] wr_addr;
  reg [4:0]             wr_burst, wr_count;
  reg                   wr_stalling;
  wire                  rsp_ready;

  begin:wr_process
    reg burst_done_i;
    always @(posedge clk) begin
      burst_done_i = 0;
      // Write side state machine
      case (wr_state)
        // --------------------------------------------
        WrIdle:
          if (slv_awvalid & slv_awready) begin
            wr_addr     <= slv_awaddr >> ByteAddrBits; // convert to word address
            wr_burst    <= slv_awlen + 1;
            wr_count    <= 0;
            wr_stalling <= weighted_rand(100 - WrThroughput);
            wr_state    <= WrBurst;
          end
        // --------------------------------------------
        WrBurst:
          begin
            if (slv_wvalid & slv_wready) begin
              memory[wr_addr + wr_count] <= slv_wdata;
              wr_count                   <= wr_count + 1;
              if (wr_count == wr_burst-1) begin
                wr_state    <= WrIdle;
                burst_done_i = 1;
                // TODO: assert(slv_wlast === 1'b1);
              end
            end

            // randomly stall writes according to 'WrThroughput' parameter
            if (wr_stalling || slv_wvalid) begin
              wr_stalling <= weighted_rand(100 - WrThroughput);
            end
          end
        // --------------------------------------------
      endcase

      // set response valid at end of burst, keep it high if response stream is blocking
      slv_bvalid <= ~rsp_ready | burst_done_i;

      if (rst) begin
        wr_state   <= WrIdle;
        slv_bvalid <= 0;
      end
    end
  end

  // response stream is ready when we're not holding data, or slave rsp channel is ready
  assign rsp_ready   = ~slv_bvalid | slv_bready;

  // write address channel is ready provided response channel isn't blocking
  assign slv_awready = (wr_state == WrIdle) && (rsp_ready);

  // write data channel is ready anytime we're processing a burst (unless we're deliberately stalling)
  assign slv_wready  = (wr_state == WrBurst) && (!wr_stalling);


  // ---------------------------------------
  // Read Instruction Fifo for Pending Reads
  // ---------------------------------------
  wire                   fifo_arvalid, fifo_arready;
  wire [MemAddrBits-1:0] fifo_araddr;
  wire [3:0]             fifo_arlen;

  // convert to memory word address
  wire [MemAddrBits-1:0] slv_araddr_word = slv_araddr >> ByteAddrBits; //[MemAddrBits+ByteAddrBits-1:ByteAddrBits];

  stream_fifo_1clk_regs #(
    .Width    (4 + MemAddrBits),
    .Depth    (NumPendingReads))
  fifo(
    .rst       (rst),
    .clk       (clk),
    //
    .din_valid (slv_arvalid),
    .din_ready (slv_arready),
    .din_data  ({slv_arlen, slv_araddr_word}),
    //
    .dout_valid(fifo_arvalid),
    .dout_ready(fifo_arready),
    .dout_data ({fifo_arlen, fifo_araddr}),
    .used      ());

  // -------------------
  // Perform Read Bursts
  // -------------------
  wire                rd_valid, rd_ready, stall_valid, stall_ready, rd_last;
  wire [DataBits-1:0] rd_data;
  reg  [3:0]          rd_count;
  reg                 rd_stalling;
  always @(posedge clk) begin
    // track number of reads in each burst
    if (rd_valid & rd_ready) begin
      if (rd_count == fifo_arlen) begin
        rd_count <= 0;
      end else begin
        rd_count <= rd_count + 1;
      end
    end
    if (rst) begin
      rd_count <= 0;
    end
  end

  assign rd_valid     = fifo_arvalid;
  assign rd_data      = memory[fifo_araddr + rd_count];
  assign rd_last      = rd_count == fifo_arlen;
  // only pull from fifo when we've reached the end of the read burst
  assign fifo_arready = (rd_last) ? rd_ready : 0;

  // ---------------------
  // Randomly Stall Reads
  // ---------------------
  always @(posedge clk) begin
    rd_stalling <= weighted_rand(100 - RdThroughput);
  end
  assign stall_valid   = (rd_stalling) ? 0 : rd_valid;
  assign rd_ready      = (rd_stalling) ? 0 : stall_ready;

  // -----------------------------------
  // Stream Buffer For Read Data Channel
  // -----------------------------------
  stream_buf_v #(
    .DataBits (DataBits+1))
  rd_buf(
    .clk       (clk),
    .rst       (rst),
    .in_valid  (stall_valid),
    .in_ready  (stall_ready),
    .in_data   ({rd_last, rd_data}),
    .out_valid (slv_rvalid),
    .out_ready (slv_rready),
    .out_data  ({slv_rlast, slv_rdata}));

  // IDs are tied low, and we always give the 'OKAY' response
  assign slv_bid    = 0;
  assign slv_bresp  = 0;
  assign slv_rid    = 0;
  assign slv_rresp  = 0;

endmodule
