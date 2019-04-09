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
// --------------------------------------------------------------------------------------
// AXI Arbiter
// --------------------------------------------------------------------------------------
// Uses round robin scheduling to share a single AXI slave with multiple AXI masters.
// This block supports pending reads from multiple masters.
//
// Optional Input and output buffers can be instantiated to improve timing, these
// will increase latency through the arbiter, but will not introduce any wait states.
//
// NOTE: This block does not support pending writes, out-of-order transactions, locking,
//       or any atypical burst requests. The 'rid', 'arsize', 'arburst', and 'arlock'
//       outputs are constant.
//
// NOTE: The slave-ports ready signals won't necessarily be high by default if
//       the input buffers are not used.
//
// --------------------------------------------------------------------------------------
module axi_arbiter #(
  parameter Ports           = 2,       // Number of AXI slave ports
            DataBits        = 64,      // Width of AXI data bus
            AddrBits        = 32,      // Width of AXI slave bus
            LenBits         = 4,       // Width of AXI burst length signals
            NumPendingReads = 6,       // Maximum number of pending read instructions
            InBuffers       = 0,       // Determines if input  buffer will be instantiated
            OutBuffer       = 1)       // Determines if output buffer will be instantiated
(
  input                        clk,
  input                        rst,
  // AXI Slave Ports: Write Address Channels
  input [Ports-1:0]            slv_awvalid,
  output [Ports-1:0]           slv_awready,
  input [Ports*AddrBits-1:0]   slv_awaddr,
  input [Ports*LenBits-1:0]    slv_awlen,
  // AXI Slave Ports: Write Data Channels
  input [Ports-1:0]            slv_wvalid,
  output [Ports-1:0]           slv_wready,
  input [Ports-1:0]            slv_wlast,
  input [Ports*DataBits/8-1:0] slv_wstrb,
  input [Ports*DataBits-1:0]   slv_wdata,
  // AXI Slave Ports: Write Response Channels
  output [Ports-1:0]           slv_bvalid,
  input [Ports-1:0]            slv_bready,
  output [Ports*2-1:0]         slv_bresp,
 	output [Ports*4-1:0]         slv_bid, // tied to '0000'
  // AXI Slave Ports: Read Address Channels
  input [Ports-1:0]            slv_arvalid,
  output [Ports-1:0]           slv_arready,
  input [Ports*AddrBits-1:0]   slv_araddr,
  input [Ports*LenBits-1:0]    slv_arlen,
  // AXI Slave Ports: Read Data Channels
  output [Ports-1:0]           slv_rvalid,
  input [Ports-1:0]            slv_rready,
  output [Ports*DataBits-1:0]  slv_rdata,
  output [Ports*2-1:0]         slv_rresp,
  output [Ports-1:0]           slv_rlast,
  output [Ports*4-1:0]         slv_rid, // tied to '0000'
  // AXI Master Port: Write Address Channel
  output                       mst_awvalid,
  input                        mst_awready,
  output [AddrBits-1:0]        mst_awaddr,
  output [LenBits-1:0]         mst_awlen,
  output [3:0]                 mst_awid, // tied to '0000'
  output [2:0]                 mst_awsize,
  output [1:0]                 mst_awburst, // tied to '01'
  output [1:0]                 mst_awlock, // tied to '00'
  // AXI Master Port: Write Data Channel
  output                       mst_wvalid,
  input                        mst_wready,
  output [3:0]                 mst_wid, // ignored
  output [DataBits/8-1:0]      mst_wstrb,
  output                       mst_wlast,
  output [DataBits-1:0]        mst_wdata,
  // AXI Master Port: Write Response Channel
  input                        mst_bvalid,
  output                       mst_bready,
  input [1:0]                  mst_bresp,
  input [3:0]                  mst_bid, // ignored
  // AXI Master Port: Read Address Channel
  output                       mst_arvalid,
  input                        mst_arready,
  output [AddrBits-1:0]        mst_araddr,
  output [LenBits-1:0]         mst_arlen,
  output [3:0]                 mst_arid, // tied to '0000'
  output [2:0]                 mst_arsize,
  output [1:0]                 mst_arburst, // tied to '01'
  output [1:0]                 mst_arlock, // tied to '00'
  // Master Port: Read Data Channel
  input                        mst_rvalid,
  output                       mst_rready,
  input [3:0]                  mst_rid, // ignored
  input [DataBits-1:0]         mst_rdata,
  input [1:0]                  mst_rresp,
  input                        mst_rlast);

  // ---------------------
  // Write Channel Arbiter
  // ---------------------
  axi_arbiter_wr #(
    .Ports          (Ports),
    .DataBits       (DataBits),
    .AddrBits       (AddrBits),
    .LenBits        (LenBits),
    .InBuffers      (InBuffers),
    .OutBuffer      (OutBuffer))
  arb_wr(
    .clk           (clk),
    .rst           (rst),
    //
    .slv_awvalid   (slv_awvalid),
    .slv_awready   (slv_awready),
    .slv_awaddr    (slv_awaddr),
    .slv_awlen     (slv_awlen),
    //
    .slv_wvalid    (slv_wvalid),
    .slv_wready    (slv_wready),
    .slv_wlast     (slv_wlast),
    .slv_wstrb     (slv_wstrb),
    .slv_wdata     (slv_wdata),
    //
    .slv_bvalid    (slv_bvalid),
    .slv_bready    (slv_bready),
    .slv_bresp     (slv_bresp),
    .slv_bid       (slv_bid),
    //
    .mst_awvalid   (mst_awvalid),
    .mst_awready   (mst_awready),
    .mst_awaddr    (mst_awaddr),
    .mst_awlen     (mst_awlen),
    .mst_awid      (mst_awid),
    .mst_awsize    (mst_awsize),
    .mst_awburst   (mst_awburst),
    .mst_awlock    (mst_awlock),
    //
    .mst_wvalid    (mst_wvalid),
    .mst_wready    (mst_wready),
    .mst_wid       (mst_wid),
    .mst_wstrb     (mst_wstrb),
    .mst_wlast     (mst_wlast),
    .mst_wdata     (mst_wdata),
    //
    .mst_bvalid    (mst_bvalid),
    .mst_bready    (mst_bready),
    .mst_bresp     (mst_bresp),
    .mst_bid       (mst_bid)
  );

  // --------------------
  // Read Channel Arbiter
  // --------------------
  axi_arbiter_rd #(
    .Ports          (Ports),
    .DataBits       (DataBits),
    .AddrBits       (AddrBits),
    .LenBits        (LenBits),
    .NumPendingReads(NumPendingReads),
    .InBuffers      (InBuffers),
    .OutBuffer      (OutBuffer))
  arb_rd(
    .clk          (clk),
    .rst          (rst),
    //
    .slv_arvalid  (slv_arvalid),
    .slv_arready  (slv_arready),
    .slv_araddr   (slv_araddr),
    .slv_arlen    (slv_arlen),
    //
    .slv_rvalid   (slv_rvalid),
    .slv_rready   (slv_rready),
    .slv_rdata    (slv_rdata),
    .slv_rresp    (slv_rresp),
    .slv_rlast    (slv_rlast),
    .slv_rid      (slv_rid),
    //
    .mst_arvalid  (mst_arvalid),
    .mst_arready  (mst_arready),
    .mst_araddr   (mst_araddr),
    .mst_arlen    (mst_arlen),
    .mst_arid     (mst_arid),
    .mst_arsize   (mst_arsize),
    .mst_arburst  (mst_arburst),
    .mst_arlock   (mst_arlock),
    //
    .mst_rvalid   (mst_rvalid),
    .mst_rready   (mst_rready),
    .mst_rid      (mst_rid),
    .mst_rdata    (mst_rdata),
    .mst_rresp    (mst_rresp),
    .mst_rlast    (mst_rlast)
   );

endmodule
