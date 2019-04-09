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
// Axi Aribter Testbench
// -----------------------------------------------------------------------------
// Implements a configurable number of stream sources and DMA modules which
// share a single Axi Slave Simulation block via an Axi Arbiter.
//
// -----------------------------------------------------------------------------
`timescale 1ns/100ps
`default_nettype none

module axi_arbiter_tb;

  localparam AxiAddrBits = 32,
             MemDataBits  = 64;
  localparam [32:0] StrmDataBits = 8;

  localparam NumPorts = 2;

  // there must be a better way...
  function[3*8-1:0] int2str(input integer i);
    reg [3*8-1:0] s;
    begin
      s[0*8 +: 8] = "0" + i      % 10;
      s[1*8 +: 8] = "0" + (i/10) % 10;
      s[2*8 +: 8] = "0" + (i/100)% 10;
      int2str = s;
    end
  endfunction

  // ---------------
  // Clock and Reset
  // ---------------
  wire clk, rst;
  clock_gen clkgen(
    .clk (clk),
    .rst (rst));

  // --------------
  // Stream Sources
  // --------------
  wire [NumPorts-1:0]              din_valid, din_ready;
  wire [StrmDataBits-1:0]          din_data[0:NumPorts-1];

  genvar i;
  generate
    for (i=0; i < NumPorts; i=i+1) begin: srcs
      stream_source #(
        .Filename   ({"in", int2str(i), ".dat"}),
        .NumSymbols (1),
        .SymbolBits ({StrmDataBits}))
      src (
        .clk       (clk),
        .rst       (rst),
        .dout_ready(din_ready[i]),
        .dout_valid(din_valid[i]),
        .dout_data (din_data[i]));
    end
  endgenerate

  // -----------------
  // APB Instructions
  // -----------------
  wire [NumPorts-1:0] wcfg_psel, wcfg_penable, wcfg_pwrite, wcfg_pready, wcfg_irq, wcfg_done;
  wire [31:0]         wcfg_paddr [0:NumPorts-1];
  wire [31:0]         wcfg_pwdata[0:NumPorts-1];
  wire [31:0]         wcfg_prdata[0:NumPorts-1];

  wire [NumPorts-1:0] rcfg_psel, rcfg_penable, rcfg_pwrite, rcfg_pready, rcfg_irq, rcfg_done;
  wire [31:0]         rcfg_paddr [0:NumPorts-1];
  wire [31:0]         rcfg_pwdata[0:NumPorts-1];
  wire [31:0]         rcfg_prdata[0:NumPorts-1];

  generate
    for (i=0; i < NumPorts; i=i+1) begin: cfgs
      apb_master_sim #(
        .Filename ({"wcfg", int2str(i), ".dat"}),
        .Verbose  (1))
      wcfg(
        .clk        (clk),
        .rst        (rst),
        .mst_paddr  (wcfg_paddr[i]),
        .mst_pwrite (wcfg_pwrite[i]),
        .mst_pwdata (wcfg_pwdata[i]),
        .mst_psel   (wcfg_psel[i]),
        .mst_penable(wcfg_penable[i]),
        .mst_pready (wcfg_pready[i]),
        .mst_prdata (wcfg_prdata[i]),
        .mst_pslverr(1'b0),
        .irq        ({30'b0, rcfg_irq[i], wcfg_irq[i]}),
        .done       (wcfg_done[i])
        );

      apb_master_sim #(
        .Filename ({"rcfg", int2str(i), ".dat"}),
        .Verbose  (1))
      rcfg(
        .clk        (clk),
        .rst        (rst),
        .mst_paddr  (rcfg_paddr[i]),
        .mst_pwrite (rcfg_pwrite[i]),
        .mst_pwdata (rcfg_pwdata[i]),
        .mst_psel   (rcfg_psel[i]),
        .mst_penable(rcfg_penable[i]),
        .mst_pready (rcfg_pready[i]),
        .mst_prdata (rcfg_prdata[i]),
        .mst_pslverr(1'b0),
        .irq        ({30'b0, rcfg_irq[i], wcfg_irq[i]}),
        .done       (rcfg_done[i])
        );
    end
  endgenerate

  // ---
  // DMA
  // ---
  wire [NumPorts-1:0]     dout_valid, dout_ready, dout_eof;
  wire [StrmDataBits-1:0] dout_data[0:NumPorts-1];
  //
  wire [NumPorts-1:0]    dma_awvalid, dma_awready;
  wire [3:0]             dma_awid[0:NumPorts-1];
  wire [AxiAddrBits-1:0] dma_awaddr[0:NumPorts-1];
  wire [3:0]             dma_awlen[0:NumPorts-1];
  wire [2:0]             dma_awsize[0:NumPorts-1];
  wire [1:0]             dma_awlock[0:NumPorts-1];
  wire [1:0]             dma_awburst[0:NumPorts-1];
  //
  wire [NumPorts-1:0]    dma_wvalid, dma_wready;
  wire [3:0]             dma_wid[0:NumPorts-1];
  wire [7:0]             dma_wstrb[0:NumPorts-1];
  wire [NumPorts-1:0]    dma_wlast;
  wire [63:0]            dma_wdata[0:NumPorts-1];
  //
  wire [NumPorts-1:0]    dma_bvalid, dma_bready;
  wire [3:0]             dma_bid[0:NumPorts-1];
  wire [1:0]             dma_bresp[0:NumPorts-1];
  //
  wire [NumPorts-1:0]    dma_arvalid, dma_arready;
  wire [3:0]             dma_arid[0:NumPorts-1];
  wire [31:0]            dma_araddr[0:NumPorts-1];
  wire [3:0]             dma_arlen[0:NumPorts-1];
  wire [2:0]             dma_arsize[0:NumPorts-1];
  wire [1:0]             dma_arlock[0:NumPorts-1];
  wire [1:0]             dma_arburst[0:NumPorts-1];
  //
  wire [NumPorts-1:0]    dma_rvalid, dma_rready;
  wire [3:0]             dma_rid[0:NumPorts-1];
  wire [63:0]            dma_rdata[0:NumPorts-1];
  wire [1:0]             dma_rresp[0:NumPorts-1];
  wire [NumPorts-1:0]    dma_rlast;

  generate
    for (i=0; i < NumPorts; i = i+1) begin: dmas
      dma_2chan_wrap #(
        .StrmDataBits  (StrmDataBits),
        .MemDataBits   (MemDataBits),
        .AddrBits      (AxiAddrBits),
        .LengthBits    (12),
        .FifoDepth     (64))
      dma (
        .clk            (clk),
        .rst            (rst),
        //
        .wcfg_paddr     (wcfg_paddr[i][5:0]),
        .wcfg_pwrite    (wcfg_pwrite[i]),
        .wcfg_pwdata    (wcfg_pwdata[i]),
        .wcfg_psel      (wcfg_psel[i]),
        .wcfg_penable   (wcfg_penable[i]),
        .wcfg_pready    (wcfg_pready[i]),
        .wcfg_prdata    (wcfg_prdata[i]),
        .wcfg_pslverr   ( ),
        .wcfg_irq       (wcfg_irq[i]),
        //
        .rcfg_paddr     (rcfg_paddr[i][5:0]),
        .rcfg_pwrite    (rcfg_pwrite[i]),
        .rcfg_pwdata    (rcfg_pwdata[i]),
        .rcfg_psel      (rcfg_psel[i]),
        .rcfg_penable   (rcfg_penable[i]),
        .rcfg_pready    (rcfg_pready[i]),
        .rcfg_prdata    (rcfg_prdata[i]),
        .rcfg_pslverr   ( ),
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

  // --------
  // Arbiter
  // --------
  wire                   arb_awvalid, arb_awready;
  wire [3:0]             arb_awid;
  wire [AxiAddrBits-1:0] arb_awaddr;
  wire [3:0]             arb_awlen;
  wire [2:0]             arb_awsize;
  wire [1:0]             arb_awlock;
  wire [1:0]             arb_awburst;
  //
  wire                   arb_wvalid, arb_wready;
  wire [3:0]             arb_wid;
  wire [7:0]             arb_wstrb;
  wire                   arb_wlast;
  wire [63:0]            arb_wdata;
  //
  wire                   arb_bvalid, arb_bready;
  wire [3:0]             arb_bid;
  wire [1:0]             arb_bresp;
  //
  wire                   arb_arvalid, arb_arready;
  wire [3:0]             arb_arid;
  wire [31:0]            arb_araddr;
  wire [3:0]             arb_arlen;
  wire [2:0]             arb_arsize;
  wire [1:0]             arb_arlock;
  wire [1:0]             arb_arburst;
  //
  wire                   arb_rvalid, arb_rready;
  wire [3:0]             arb_rid;
  wire [63:0]            arb_rdata;
  wire [1:0]             arb_rresp;
  wire                   arb_rlast;

  axi_arbiter #(
    .Ports           (NumPorts),
    .DataBits        (MemDataBits),
    .AddrBits        (AxiAddrBits),
    .LenBits         (4),
    .NumPendingReads (3),
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
    .slv_rid      (),

    .mst_awvalid  (arb_awvalid),
    .mst_awready  (arb_awready),
    .mst_awaddr   (arb_awaddr),
    .mst_awlen    (arb_awlen),
    .mst_awid     (arb_awid),
    .mst_awsize   (arb_awsize),
    .mst_awlock   (arb_awlock),
    .mst_awburst  (arb_awburst),
    //
    .mst_wvalid   (arb_wvalid),
    .mst_wready   (arb_wready),
    .mst_wlast    (arb_wlast),
    .mst_wstrb    (arb_wstrb),
    .mst_wid      (arb_wid),
    .mst_wdata    (arb_wdata),
    //
    .mst_bvalid   (arb_bvalid),
    .mst_bready   (arb_bready),
    .mst_bid      (arb_bid),
    .mst_bresp    (arb_bresp),
    //
    .mst_arvalid  (arb_arvalid),
    .mst_arready  (arb_arready),
    .mst_arid     (arb_arid),
    .mst_araddr   (arb_araddr),
    .mst_arlen    (arb_arlen),
    .mst_arsize   (arb_arsize),
    .mst_arlock   (arb_arlock),
    .mst_arburst  (arb_arburst),
    //
    .mst_rvalid   (arb_rvalid),
    .mst_rready   (arb_rready),
    .mst_rid      (arb_rid),
    .mst_rdata    (arb_rdata),
    .mst_rresp    (arb_rresp),
    .mst_rlast    (arb_rlast)
    );

  // Axi Slave
  axi_slave_sim #(
    .DataBits       (MemDataBits),
    .AxiAddrBits    (AxiAddrBits),
    .MemAddrBits    (12),
    .NumPendingReads(3),
    .WrThroughput   (57),
    .RdThroughput   (61))
  memory (
    .clk          (clk),
    .rst          (rst),
    //
    .slv_awvalid  (arb_awvalid),
    .slv_awready  (arb_awready),
    .slv_awid     (arb_awid),
    .slv_awaddr   (arb_awaddr),
    .slv_awlen    (arb_awlen),
    .slv_awsize   (arb_awsize),
    .slv_awlock   (arb_awlock),
    .slv_awburst  (arb_awburst),
    //
    .slv_wvalid   (arb_wvalid),
    .slv_wready   (arb_wready),
    .slv_wid      (arb_wid),
    .slv_wstrb    (arb_wstrb),
    .slv_wlast    (arb_wlast),
    .slv_wdata    (arb_wdata),
    //
    .slv_bvalid   (arb_bvalid),
    .slv_bready   (arb_bready),
    .slv_bid      (arb_bid),
    .slv_bresp    (arb_bresp),
    //
    .slv_arvalid  (arb_arvalid),
    .slv_arready  (arb_arready),
    .slv_arid     (arb_arid),
    .slv_araddr   (arb_araddr),
    .slv_arlen    (arb_arlen),
    .slv_arsize   (arb_arsize),
    .slv_arlock   (arb_arlock),
    .slv_arburst  (arb_arburst),
    //
    .slv_rvalid   (arb_rvalid),
    .slv_rready   (arb_rready),
    .slv_rid      (arb_rid),
    .slv_rdata    (arb_rdata),
    .slv_rresp    (arb_rresp),
    .slv_rlast    (arb_rlast));


  // ------------
  // Stream Sink
  // ------------
  wire [NumPorts-1:0] done, err;
  generate
    for (i=0; i < NumPorts; i=i+1) begin: snks
      stream_sink #(
        .FilenameDump ({"out",int2str(i),".dat"}),
        .FilenameRef  ({"ref",int2str(i),".dat"}),
        .CheckData    (1),
        .NumSymbols   (2),
        .SymbolBits   ({StrmDataBits, 32'b1}))
      snk (
        .clk       (clk),
        .rst       (rst),
        .din_ready (dout_ready[i]),
        .din_valid (dout_valid[i]),
        .din_data  ({dout_data[i], dout_eof[i]}),
        .done      (done[i]),
        .err       (err[i]));
    end
  endgenerate

  // ----------
  // Monitoring
  // ----------
  reg        finished;
  always @(posedge clk) begin
    if (!finished) begin
      if (&done) begin
        if (|err)
          $display("***SIMULATION FAILED***");
        else
          $display("***SIMULATION PASSED***");
        //$finish
        finished = 1;
      end
    end
    if (rst)
      finished = 0;
  end
endmodule

