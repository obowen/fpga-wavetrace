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
// Dma Testbench
// -----------------------------------------------------------------------------
// Testbench for the 'dma-2chan-wrap' module which contains a memory-to-stream
// and a stream-to-memory DMA module.
//
// -----------------------------------------------------------------------------
`timescale 1ns/100ps
`default_nettype none

module dma_2chan_wrap_tb;

  localparam AxiAddrBits = 32,
             MemDataBits  = 64;
  localparam [32:0] StrmDataBits = 32;

  // ---------------
  // Clock and Reset
  // ---------------
  wire clk, rst;
  clock_gen clkgen(
    .clk (clk),
    .rst (rst));

  // -------------
  // Stream Source
  // -------------
  wire       din_valid, din_ready, din_eof;
  wire [StrmDataBits-1:0] din_data;
  stream_source #(
    .Filename     ("in.dat"),
    .NumSymbols   (2),
    .SymbolBits   ({StrmDataBits, 32'b1}))
  src (
    .clk       (clk),
    .rst       (rst),
    .dout_ready(din_ready),
    .dout_valid(din_valid),
    .dout_data ({din_data, din_eof}));

  // ----------------
  // APB Instructions
  // ----------------
  wire        cfg_psel, cfg_penable, cfg_pwrite, cfg_pready, cfg_pslverr, cfg_done, cfg_err;
  wire [31:0] cfg_paddr, cfg_pwdata, cfg_prdata;

  wire        wcfg_psel, wcfg_penable, wcfg_pready, wcfg_pslverr, wcfg_irq;
  wire        rcfg_psel, rcfg_penable, rcfg_pready, rcfg_pslverr, rcfg_irq;
  wire [31:0] wcfg_prdata, rcfg_prdata;

  apb_master_sim #(
    .Filename ("cfg.dat"))
  cfg(
    .clk        (clk),
    .rst        (rst),
    .mst_paddr  (cfg_paddr),
    .mst_pwrite (cfg_pwrite),
    .mst_pwdata (cfg_pwdata),
    .mst_psel   (cfg_psel),
    .mst_penable(cfg_penable),
    .mst_pready (cfg_pready),
    .mst_prdata (cfg_prdata),
    .mst_pslverr(1'b0),
    .irq        ({30'b0, rcfg_irq, wcfg_irq}),
    .done       (cfg_done),
    .err        (cfg_err)
    );

  // Demux between wcfg and rcfg
  wire [1:0]      dmux_psel, dmux_penable, dmux_pready, dmux_pslverr;
  wire [2*32-1:0] dmux_prdata;
  apb_demux #(
    .NumPorts(2),
    .AddrBits(32))
  cfg_demux(
    .clk          (clk),
    .rst          (rst),
    //
    .slv_paddr    (cfg_paddr),
    .slv_psel     (cfg_psel),
    .slv_penable  (cfg_penable),
    .slv_pready   (cfg_pready),
    .slv_prdata   (cfg_prdata),
    .slv_pslverr  (cfg_pslverr),
    //
    .mst_psel     ({rcfg_psel,    wcfg_psel}),
    .mst_penable  ({rcfg_penable, wcfg_penable}),
    .mst_pready   ({rcfg_pready,  wcfg_pready}),
    .mst_prdata   ({rcfg_prdata,  wcfg_prdata}),
    .mst_pslverr  ({rcfg_pslverr,  wcfg_pslverr}));

  // ----
  // DMA
  // ----
  wire                    dout_valid, dout_ready, dout_eof;
  wire [StrmDataBits-1:0] dout_data;
  //
  wire                   dma_awvalid, dma_awready;
  wire [3:0]             dma_awid;
  wire [AxiAddrBits-1:0] dma_awaddr;
  wire [3:0]             dma_awlen;
  wire [2:0]             dma_awsize;
  wire [1:0]             dma_awlock;
  wire [1:0]             dma_awburst;
  //
  wire                   dma_wvalid, dma_wready;
  wire [3:0]             dma_wid;
  wire [7:0]             dma_wstrb;
  wire                   dma_wlast;
  wire [63:0]            dma_wdata;
  //
  wire                   dma_bvalid, dma_bready;
  wire [3:0]             dma_bid;
  wire [1:0]             dma_bresp;
  //
  wire                   dma_arvalid, dma_arready;
  wire [3:0]             dma_arid;
  wire [31:0]            dma_araddr;
  wire [3:0]             dma_arlen;
  wire [2:0]             dma_arsize;
  wire [1:0]             dma_arlock;
  wire [1:0]             dma_arburst;
  //
  wire                   dma_rvalid, dma_rready;
  wire [3:0]             dma_rid;
  wire [63:0]            dma_rdata;
  wire [1:0]             dma_rresp;
  wire                   dma_rlast;

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
    .wcfg_paddr      (cfg_paddr[5:0]),
    .wcfg_pwrite     (cfg_pwrite),
    .wcfg_pwdata     (cfg_pwdata),
    .wcfg_psel       (wcfg_psel),
    .wcfg_penable    (wcfg_penable),
    .wcfg_pready     (wcfg_pready),
    .wcfg_prdata     (wcfg_prdata),
    .wcfg_pslverr    (wcfg_pslverr),
    .wcfg_irq        (wcfg_irq),
    //
    .rcfg_paddr      (cfg_paddr[5:0]),
    .rcfg_pwrite     (cfg_pwrite),
    .rcfg_pwdata     (cfg_pwdata),
    .rcfg_psel       (rcfg_psel),
    .rcfg_penable    (rcfg_penable),
    .rcfg_pready     (rcfg_pready),
    .rcfg_prdata     (rcfg_prdata),
    .rcfg_pslverr    (rcfg_pslverr ),
    .rcfg_irq        (rcfg_irq),
    //
    .din_valid      (din_valid),
    .din_ready      (din_ready),
    .din_data       (din_data),
    .din_eof        (din_eof),
    //
    .dout_valid     (dout_valid),
    .dout_ready     (dout_ready),
    .dout_data      (dout_data),
    .dout_eof       (dout_eof),
    //
    .mst_awvalid    (dma_awvalid),
    .mst_awready    (dma_awready),
    .mst_awid       (dma_awid),
    .mst_awaddr     (dma_awaddr),
    .mst_awlen      (dma_awlen),
    .mst_awsize     (dma_awsize),
    .mst_awlock     (dma_awlock),
    .mst_awburst    (dma_awburst),
    //
    .mst_wvalid     (dma_wvalid),
    .mst_wready     (dma_wready),
    .mst_wid        (dma_wid),
    .mst_wstrb      (dma_wstrb),
    .mst_wlast      (dma_wlast),
    .mst_wdata      (dma_wdata),
    //
    .mst_bvalid     (dma_bvalid),
    .mst_bready     (dma_bready),
    .mst_bid        (dma_bid),
    .mst_bresp      (dma_bresp),
    //
    .mst_arvalid    (dma_arvalid),
    .mst_arready    (dma_arready),
    .mst_arid       (dma_arid),
    .mst_araddr     (dma_araddr),
    .mst_arlen      (dma_arlen),
    .mst_arsize     (dma_arsize),
    .mst_arlock     (dma_arlock),
    .mst_arburst    (dma_arburst),
    //
    .mst_rvalid     (dma_rvalid),
    .mst_rready     (dma_rready),
    .mst_rid        (dma_rid),
    .mst_rdata      (dma_rdata),
    .mst_rresp      (dma_rresp),
    .mst_rlast      (dma_rlast)
    );

  // Axi Slave
  axi_slave_sim #(
    .DataBits       (MemDataBits),
    .AxiAddrBits    (AxiAddrBits),
    .MemAddrBits    (12),
    .NumPendingReads(3),
    .WrThroughput   (63),
    .RdThroughput   (57))
  memory (
    .clk          (clk),
    .rst          (rst),
    //
    .slv_awvalid  (dma_awvalid),
    .slv_awready  (dma_awready),
    .slv_awid     (dma_awid),
    .slv_awaddr   (dma_awaddr),
    .slv_awlen    (dma_awlen),
    .slv_awsize   (dma_awsize),
    .slv_awlock   (dma_awlock),
    .slv_awburst  (dma_awburst),
    //
    .slv_wvalid   (dma_wvalid),
    .slv_wready   (dma_wready),
    .slv_wid      (dma_wid),
    .slv_wstrb    (dma_wstrb),
    .slv_wlast    (dma_wlast),
    .slv_wdata    (dma_wdata),
    //
    .slv_bvalid   (dma_bvalid),
    .slv_bready   (dma_bready),
    .slv_bid      (dma_bid),
    .slv_bresp    (dma_bresp),
    //
    .slv_arvalid  (dma_arvalid),
    .slv_arready  (dma_arready),
    .slv_arid     (dma_arid),
    .slv_araddr   (dma_araddr),
    .slv_arlen    (dma_arlen),
    .slv_arsize   (dma_arsize),
    .slv_arlock   (dma_arlock),
    .slv_arburst  (dma_arburst),
    //
    .slv_rvalid   (dma_rvalid),
    .slv_rready   (dma_rready),
    .slv_rid      (dma_rid),
    .slv_rdata    (dma_rdata),
    .slv_rresp    (dma_rresp),
    .slv_rlast    (dma_rlast),
    //
    .dump_memory  (1'b0));


  // ------------
  // Stream Sink
  // ------------
  wire       done, err;
  stream_sink #(
    .FilenameDump ("out.dat"),
    .FilenameRef  ("ref.dat"),
    .CheckData    (1),
    .NumSymbols   (2),
    .SymbolBits   ({StrmDataBits, 32'b1}))
  snk (
    .clk       (clk),
    .rst       (rst),
    .din_ready (dout_ready),
    .din_valid (dout_valid),
    .din_data  ({dout_data, dout_eof}),
    .done      (done),
    .err       (err));

  // ----------
  // Monitoring
  // ----------
  reg        finished;
  always @(posedge clk) begin
    if (!finished) begin
      if (done) begin
        if (err)
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
