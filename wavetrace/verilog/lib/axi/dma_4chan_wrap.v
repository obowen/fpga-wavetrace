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
// -------------------------------------------------------------------------------
// Dma 4-Channel Wrapper
// -------------------------------------------------------------------------------
// Instantiates two dma_2chan_wrap modules and an AXI arbiter
//
// -------------------------------------------------------------------------------
module dma_4chan_wrap #(
  parameter StrmDataBits  = 8,
  parameter MemDataBits   = 64,
  parameter AddrBits      = 32,
  parameter LengthBits    = 16,
  parameter FifoDepth     = 64)
(
  input                      clk,
  input                      rst,
  // APB Interface for reader (mem2strm)
  input [5:0]                rcfg0_paddr,
  input                      rcfg0_psel,
  input                      rcfg0_penable,
  input                      rcfg0_pwrite,
  input [31:0]               rcfg0_pwdata,
  output                     rcfg0_pready,
  output [31:0]              rcfg0_prdata,
  output                     rcfg0_pslverr,
  output                     rcfg0_irq,
  // APB config interface for writer (strm2mem)
  input [5:0]                wcfg0_paddr,
  input                      wcfg0_psel,
  input                      wcfg0_penable,
  input                      wcfg0_pwrite,
  input [31:0]               wcfg0_pwdata,
  output                     wcfg0_pready,
  output [31:0]              wcfg0_prdata,
  output                     wcfg0_pslverr,
  output                     wcfg0_irq,
  // APB Interface for reader (mem2strm)
  input [5:0]                rcfg1_paddr,
  input                      rcfg1_psel,
  input                      rcfg1_penable,
  input                      rcfg1_pwrite,
  input [31:0]               rcfg1_pwdata,
  output                     rcfg1_pready,
  output [31:0]              rcfg1_prdata,
  output                     rcfg1_pslverr,
  output                     rcfg1_irq,
  // APB config interface for wr1ter (strm2mem)
  input [5:0]                wcfg1_paddr,
  input                      wcfg1_psel,
  input                      wcfg1_penable,
  input                      wcfg1_pwrite,
  input [31:0]               wcfg1_pwdata,
  output                     wcfg1_pready,
  output [31:0]              wcfg1_prdata,
  output                     wcfg1_pslverr,
  output                     wcfg1_irq,
  // Input Data Stream
  input                      din0_valid,
  output                     din0_ready,
  input [StrmDataBits-1:0]   din0_data,
  // Output Data Stream
  output                     dout0_valid,
  input                      dout0_ready,
  output [StrmDataBits-1:0]  dout0_data,
  output                     dout0_eof,
  // Input Data Stream
  input                      din1_valid,
  output                     din1_ready,
  input [StrmDataBits-1:0]   din1_data,
  // Output Data Stream
  output                     dout1_valid,
  input                      dout1_ready,
  output [StrmDataBits-1:0]  dout1_data,
  output                     dout1_eof,
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

  localparam NumPorts = 2;

  wire [NumPorts-1:0]     din_valid, din_ready;
  wire [StrmDataBits-1:0] din_data[0:NumPorts-1];
  wire [NumPorts-1:0]     dout_valid, dout_ready, dout_eof;
  wire [StrmDataBits-1:0] dout_data[0:NumPorts-1];

  wire [NumPorts-1:0]     wcfg_psel, wcfg_penable, wcfg_pwrite, wcfg_pready, wcfg_irq, wcfg_pslverr;
  wire [5:0]              wcfg_paddr [0:NumPorts-1];
  wire [31:0]             wcfg_pwdata[0:NumPorts-1];
  wire [31:0]             wcfg_prdata[0:NumPorts-1];

  wire [NumPorts-1:0]     rcfg_psel, rcfg_penable, rcfg_pwrite, rcfg_pready, rcfg_irq, rcfg_pslverr;
  wire [5:0]              rcfg_paddr [0:NumPorts-1];
  wire [31:0]             rcfg_pwdata[0:NumPorts-1];
  wire [31:0]             rcfg_prdata[0:NumPorts-1];

  //
  wire [NumPorts-1:0]     dma_awvalid, dma_awready;
  wire [3:0]              dma_awid[0:NumPorts-1];
  wire [AddrBits-1:0]     dma_awaddr[0:NumPorts-1];
  wire [3:0]              dma_awlen[0:NumPorts-1];
  wire [2:0]              dma_awsize[0:NumPorts-1];
  wire [1:0]              dma_awlock[0:NumPorts-1];
  wire [1:0]              dma_awburst[0:NumPorts-1];
  //
  wire [NumPorts-1:0]     dma_wvalid, dma_wready;
  wire [3:0]              dma_wid[0:NumPorts-1];
  wire [7:0]              dma_wstrb[0:NumPorts-1];
  wire [NumPorts-1:0]     dma_wlast;
  wire [MemDataBits-1:0]  dma_wdata[0:NumPorts-1];
  //
  wire [NumPorts-1:0]     dma_bvalid, dma_bready;
  wire [3:0]              dma_bid[0:NumPorts-1];
  wire [1:0]              dma_bresp[0:NumPorts-1];
  //
  wire [NumPorts-1:0]     dma_arvalid, dma_arready;
  wire [3:0]              dma_arid[0:NumPorts-1];
  wire [31:0]             dma_araddr[0:NumPorts-1];
  wire [3:0]              dma_arlen[0:NumPorts-1];
  wire [2:0]              dma_arsize[0:NumPorts-1];
  wire [1:0]              dma_arlock[0:NumPorts-1];
  wire [1:0]              dma_arburst[0:NumPorts-1];
  //
  wire [NumPorts-1:0]     dma_rvalid, dma_rready;
  wire [3:0]              dma_rid[0:NumPorts-1];
  wire [MemDataBits-1:0]  dma_rdata[0:NumPorts-1];
  wire [1:0]              dma_rresp[0:NumPorts-1];
  wire [NumPorts-1:0]     dma_rlast;

  assign wcfg_paddr[1]                 = wcfg1_paddr;
  assign wcfg_paddr[0]                 = wcfg0_paddr;
  assign wcfg_pwdata[1]                = wcfg1_pwdata;
  assign wcfg_pwdata[0]                = wcfg0_pwdata;
  assign wcfg_pwrite                   = {wcfg1_pwrite,  wcfg0_pwrite};
  assign wcfg_psel                     = {wcfg1_psel,    wcfg0_psel};
  assign wcfg_penable                  = {wcfg1_penable, wcfg0_penable};
  //
  assign wcfg1_prdata                  = wcfg_prdata[1];
  assign wcfg0_prdata                  = wcfg_prdata[0];
  assign {wcfg1_pready, wcfg0_pready}  = wcfg_pready;
  assign {wcfg1_irq,    wcfg0_irq}     = wcfg_irq;
  assign {wcfg1_pslverr, wcfg0_pslverr}= wcfg_pslverr;

  assign rcfg_paddr[1]                 = rcfg1_paddr;
  assign rcfg_paddr[0]                 = rcfg0_paddr;
  assign rcfg_pwdata[1]                = rcfg1_pwdata;
  assign rcfg_pwdata[0 ]               = rcfg0_pwdata;
  assign rcfg_pwrite                   = {rcfg1_pwrite,  rcfg0_pwrite};
  assign rcfg_psel                     = {rcfg1_psel,    rcfg0_psel};
  assign rcfg_penable                  = {rcfg1_penable, rcfg0_penable};
  //
  assign rcfg1_prdata                  = rcfg_prdata[1];
  assign rcfg0_prdata                  = rcfg_prdata[0];
  assign {rcfg1_pready, rcfg0_pready}  = rcfg_pready;
  assign {rcfg1_irq,    rcfg0_irq}     = rcfg_irq;
  assign {rcfg1_pslverr, rcfg0_pslverr}= rcfg_pslverr;

  assign din_data[1]                = din1_data;
  assign din_data[0]                = din0_data;
  assign din_valid                  = {din1_valid, din0_valid};
  assign {din1_ready, din0_ready}   = din_ready;

  assign dout1_data                 = dout_data[1];
  assign dout0_data                 = dout_data[0];
  assign {dout1_valid, dout0_valid} = dout_valid;
  assign {dout1_eof,   dout0_eof}   = dout_eof;
  assign dout_ready                 = {dout1_ready, dout0_ready};

  genvar i;
  generate
    for (i=0; i < NumPorts; i = i+1) begin: dmas
      dma_2chan_wrap #(
        .StrmDataBits  (StrmDataBits),
        .MemDataBits   (MemDataBits),
        .AddrBits      (AddrBits),
        .LengthBits    (LengthBits),
        .FifoDepth     (FifoDepth))
      dma (
        .clk            (clk),
        .rst            (rst),
        //
        .wcfg_paddr     (wcfg_paddr[i]),
        .wcfg_pwrite    (wcfg_pwrite[i]),
        .wcfg_pwdata    (wcfg_pwdata[i]),
        .wcfg_psel      (wcfg_psel[i]),
        .wcfg_penable   (wcfg_penable[i]),
        .wcfg_pready    (wcfg_pready[i]),
        .wcfg_prdata    (wcfg_prdata[i]),
        .wcfg_pslverr   (wcfg_pslverr[i]),
        .wcfg_irq       (wcfg_irq[i]),
        //
        .rcfg_paddr     (rcfg_paddr[i]),
        .rcfg_pwrite    (rcfg_pwrite[i]),
        .rcfg_pwdata    (rcfg_pwdata[i]),
        .rcfg_psel      (rcfg_psel[i]),
        .rcfg_penable   (rcfg_penable[i]),
        .rcfg_pready    (rcfg_pready[i]),
        .rcfg_prdata    (rcfg_prdata[i]),
        .rcfg_pslverr   (rcfg_pslverr[i]),
        .rcfg_irq       (rcfg_irq[i]),
        //
        .din_valid      (din_valid[i]),
        .din_ready      (din_ready[i]),
        .din_data       (din_data[i]),
        //
        .dout_valid     (dout_valid[i]),
        .dout_ready     (dout_ready[i]),
        .dout_data      (dout_data[i]),
        .dout_eof       (dout_eof[i]),
        //
        .mst_awvalid    (dma_awvalid[i]),
        .mst_awready    (dma_awready[i]),
        .mst_awid       (dma_awid[i]),
        .mst_awaddr     (dma_awaddr[i]),
        .mst_awlen      (dma_awlen[i]),
        .mst_awsize     (dma_awsize[i]),
        .mst_awlock     (dma_awlock[i]),
        .mst_awburst    (dma_awburst[i]),
        //
        .mst_wvalid     (dma_wvalid[i]),
        .mst_wready     (dma_wready[i]),
        .mst_wid        (dma_wid[i]),
        .mst_wstrb      (dma_wstrb[i]),
        .mst_wlast      (dma_wlast[i]),
        .mst_wdata      (dma_wdata[i]),
        //
        .mst_bvalid     (dma_bvalid[i]),
        .mst_bready     (dma_bready[i]),
        .mst_bid        (dma_bid[i]),
        .mst_bresp      (dma_bresp[i]),
        //
        .mst_arvalid    (dma_arvalid[i]),
        .mst_arready    (dma_arready[i]),
        .mst_arid       (dma_arid[i]),
        .mst_araddr     (dma_araddr[i]),
        .mst_arlen      (dma_arlen[i]),
        .mst_arsize     (dma_arsize[i]),
        .mst_arlock     (dma_arlock[i]),
        .mst_arburst    (dma_arburst[i]),
        //
        .mst_rvalid     (dma_rvalid[i]),
        .mst_rready     (dma_rready[i]),
        .mst_rid        (dma_rid[i]),
        .mst_rdata      (dma_rdata[i]),
        .mst_rresp      (dma_rresp[i]),
        .mst_rlast      (dma_rlast[i])
        );
    end
  endgenerate


  axi_arbiter #(
    .Ports           (NumPorts),
    .DataBits        (MemDataBits),
    .AddrBits        (AddrBits),
    .LenBits         (4),
    .NumPendingReads (6),
    .InBuffers       (0),
    .OutBuffer       (1))
  arbiter (
    .clk          (clk),
    .rst          (rst),

    .slv_awvalid  (dma_awvalid),
    .slv_awready  (dma_awready),
    .slv_awaddr   ({dma_awaddr[1], dma_awaddr[0]}),
    .slv_awlen    ({dma_awlen[1],  dma_awlen[0]}),

    .slv_wvalid   (dma_wvalid),
    .slv_wready   (dma_wready),
    .slv_wlast    (dma_wlast),
    .slv_wstrb    ({dma_wstrb[1], dma_wstrb[0]}),
    .slv_wdata    ({dma_wdata[1], dma_wdata[0]}),

    .slv_bvalid   (dma_bvalid),
    .slv_bready   (dma_bready),
    .slv_bresp    ({dma_bresp[1], dma_bresp[0]}),
    .slv_bid      ({dma_bid[1],   dma_bid[0]}),

    .slv_arvalid  (dma_arvalid),
    .slv_arready  (dma_arready),
    .slv_araddr   ({dma_araddr[1], dma_araddr[0]}),
    .slv_arlen    ({dma_arlen[1],  dma_arlen[0]}),

    .slv_rvalid   (dma_rvalid),
    .slv_rready   (dma_rready),
    .slv_rdata    ({dma_rdata[1], dma_rdata[0]}),
    .slv_rresp    ({dma_rresp[1], dma_rresp[0]}),
    .slv_rlast    ({dma_rlast[1], dma_rlast[0]}),
    .slv_rid      ({dma_rid[1],   dma_rid[0]}),

    .mst_awvalid  (mst_awvalid),
    .mst_awready  (mst_awready),
    .mst_awaddr   (mst_awaddr),
    .mst_awlen    (mst_awlen),
    .mst_awid     (mst_awid),
    .mst_awsize   (mst_awsize),
    .mst_awlock   (mst_awlock),
    .mst_awburst  (mst_awburst),
    //
    .mst_wvalid   (mst_wvalid),
    .mst_wready   (mst_wready),
    .mst_wlast    (mst_wlast),
    .mst_wstrb    (mst_wstrb),
    .mst_wid      (mst_wid),
    .mst_wdata    (mst_wdata),
    //
    .mst_bvalid   (mst_bvalid),
    .mst_bready   (mst_bready),
    .mst_bid      (mst_bid),
    .mst_bresp    (mst_bresp),
    //
    .mst_arvalid  (mst_arvalid),
    .mst_arready  (mst_arready),
    .mst_arid     (mst_arid),
    .mst_araddr   (mst_araddr),
    .mst_arlen    (mst_arlen),
    .mst_arsize   (mst_arsize),
    .mst_arlock   (mst_arlock),
    .mst_arburst  (mst_arburst),
    //
    .mst_rvalid   (mst_rvalid),
    .mst_rready   (mst_rready),
    .mst_rid      (mst_rid),
    .mst_rdata    (mst_rdata),
    .mst_rresp    (mst_rresp),
    .mst_rlast    (mst_rlast)
    );

endmodule

