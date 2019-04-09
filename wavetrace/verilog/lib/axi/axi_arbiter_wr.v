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
// AXI Arbiter for Write Channels
// --------------------------------------------------------------------------------------
// Uses round robin scheduling to share the Write channels of a single AXI slave with
// multiple AXI masters.
//
// Optional Input and output buffers can be instantiated to improve timing, these
// will increase latency through the arbiter, but will not introduce any wait states.
//
// NOTE: This block does not support pending writes, out-of-order writes, locking, or
//       any atypical burst requests. The 'rid', 'arsize', 'arburst', and 'arlock'
//       outputs are constant.
//
// NOTE: slv_awready and slv_wready won't necessarily be high by default if
//       the input buffer is not used.
//
// --------------------------------------------------------------------------------------
module axi_arbiter_wr #(
  parameter Ports           = 2,       // Number of AXI slave ports
            DataBits        = 64,      // Width of AXI data bus
            AddrBits        = 32,      // Width of AXI slave bus
            LenBits         = 4,       // Width of AXI burst length signals
            InBuffers       = 0,       // Determines if input  buffer will be instantiated
            OutBuffer       = 1)       // Determines if output buffer will be instantiated
(
  input                         clk,
  input                         rst,
  // AXI Slave Ports: Write Address Channels
  input  [Ports-1:0]            slv_awvalid,
  output [Ports-1:0]            slv_awready,
	input  [Ports*AddrBits-1:0]   slv_awaddr,
  input  [Ports*LenBits-1:0]    slv_awlen,
  // AXI Slave Ports: Write Data Channels
  input  [Ports-1:0]            slv_wvalid,
  output [Ports-1:0]            slv_wready,
  input  [Ports-1:0]            slv_wlast,
  input  [Ports*DataBits/8-1:0] slv_wstrb,
  input  [Ports*DataBits-1:0]   slv_wdata,
  // AXI Slave Ports: Write Response Channels
	output reg [Ports-1:0]        slv_bvalid,
	input      [Ports-1:0]        slv_bready,
	output reg [Ports*2-1:0]      slv_bresp,
 	output     [Ports*4-1:0]      slv_bid,     // tied to '0000'
  // AXI Master Port: Write Address Channel
  output                        mst_awvalid,
  input                         mst_awready,
	output [AddrBits-1:0]         mst_awaddr,
  output [LenBits-1:0]          mst_awlen,
	output [3:0]                  mst_awid,    // tied to '0000'
  output [2:0]                  mst_awsize,  // indicates bytes per word
  output [1:0]                  mst_awburst, // tied to '01'
  output [1:0]                  mst_awlock,  // tied to '00'
  // AXI Master Port: Write Data Channel
  output                        mst_wvalid,
  input                         mst_wready,
  output [3:0]                  mst_wid,     // tied to '0000'
  output [DataBits/8-1:0]       mst_wstrb,
  output                        mst_wlast,
  output [DataBits-1:0]         mst_wdata,
  // AXI Master Port: Write Response Channel
	input                         mst_bvalid,
	output                        mst_bready,
	input [1:0]                   mst_bresp,
  input [3:0]                   mst_bid);    // ignored

`include "util.vh"
`include "axi_arbiter.vh"

  localparam BytesPerWord = DataBits / 8;

  // -----------------------------------------------
  // Optional Input Buffers (and convert to arrays)
  // -----------------------------------------------
  wire [Ports-1:0]      buf_awvalid;
  reg  [Ports-1:0]      buf_awready;
	wire [AddrBits-1:0]   buf_awaddr[0:Ports-1];
  wire [LenBits-1:0]    buf_awlen [0:Ports-1];
  //
  wire [Ports-1:0]      buf_wvalid, buf_wlast;
  reg  [Ports-1:0]      buf_wready;
  wire [DataBits/8-1:0] buf_wstrb[0:Ports-1];
  wire [DataBits-1:0]   buf_wdata[0:Ports-1];

  genvar n;
  generate
    for (n=0; n < Ports; n=n+1) begin: inbufs
      if (InBuffers) begin: inbuf
        stream_buf_r #(
          .DataBits (LenBits + AddrBits))
        inbuf_aw(
          .clk       (clk),
          .rst       (rst),
          .in_valid  (slv_awvalid[n]),
          .in_ready  (slv_awready[n]),
          .in_data   ({slv_awlen[n*LenBits +: LenBits],
                       slv_awaddr[n*AddrBits +: AddrBits]}),
          .out_valid (buf_awvalid[n]),
          .out_ready (buf_awready[n]),
          .out_data  ({buf_awlen[n],
                       buf_awaddr[n]})
        );
        stream_buf_r #(
          .DataBits (1 + DataBits/8 + DataBits))
        inbuf_a(
          .clk       (clk),
          .rst       (rst),
          .in_valid  (slv_wvalid[n]),
          .in_ready  (slv_wready[n]),
          .in_data   ({slv_wlast[n],
                       slv_wstrb[n*DataBits/8 +: DataBits/8],
                       slv_wdata[n*DataBits   +: DataBits]}),
          .out_valid (buf_wvalid[n]),
          .out_ready (buf_wready[n]),
          .out_data  ({buf_wlast[n],
                       buf_wstrb[n],
                       buf_wdata[n]})
        );

      end else begin: no_inbuf
        assign buf_awvalid[n] = slv_awvalid[n];
        assign buf_awlen[n]   = slv_awlen[n*LenBits +: LenBits];
        assign buf_awaddr[n]  = slv_awaddr[n*AddrBits +: AddrBits];
        assign slv_awready[n] = buf_awready[n];

        assign buf_wvalid[n]  = slv_wvalid[n];
        assign buf_wlast[n]   = slv_wlast[n];
        assign buf_wstrb[n]   = slv_wstrb[n*DataBits/8 +: DataBits/8];
        assign buf_wdata[n]   = slv_wdata[n*DataBits   +: DataBits];
        assign slv_wready[n]  = buf_wready[n];
      end
    end
  endgenerate

  //------------------------
  // Round Robin Scheduling
  //------------------------
  localparam Select       = 0,
             WaitWrChan   = 1,
             WaitAddrChan = 2,
             WaitRspChan  = 3;

  reg [1:0]              state, state_nxt;
  reg [Ports-1:0]        grant, grant_nxt, request;
  reg                    select_new_port;
  reg [clog2(Ports)-1:0] sel;
  //
  reg                    sel_awvalid;
  wire                   sel_awready;
	reg [AddrBits-1:0]     sel_awaddr;
  reg [LenBits-1:0]      sel_awlen;
  //
  reg                    sel_wvalid, sel_wlast;
  wire                   sel_wready;
  reg [DataBits/8-1:0]   sel_wstrb;
  reg [DataBits-1:0]     sel_wdata;
  //
  wire                   sel_bvalid;
  reg                    sel_bready;
  wire [1:0]             sel_bresp;

  // helper signal to detect final transaction of a write burst
  wire wr_burst_done     = (sel_wvalid & sel_wready & sel_wlast);

  always @(*) begin

    state_nxt         = state;
    grant_nxt         = grant;
    select_new_port   = 0;

    // by default, no data flows on the address or data channel
    sel_awvalid       = 0;
    buf_awready       = 0;
    sel_wvalid        = 0;
    buf_wready        = 0;

    // get index of currently selected slave port
    sel               = onehot2bin(grant, Ports);

    // connect the response channel to the selected port.
    // (it's okay to leave this hooked up regardless of our state because the AXI spec
    //  requires the response to only be valid on, or after, the 'last' write data transaction)
    slv_bvalid        = 0;
    slv_bvalid[sel]   = sel_bvalid;
    sel_bready        = slv_bready[sel];

    // muxes to select write-address channel
    sel_awlen         = buf_awlen  [sel];
    sel_awaddr        = buf_awaddr [sel];

    // muxes to select write-data channel
    sel_wdata         = buf_wdata[sel];
    sel_wstrb         = buf_wstrb[sel];
    sel_wlast         = buf_wlast[sel];

    // response data is simply connected to all ports
    slv_bresp         = {Ports{sel_bresp}};

    case (state)
      // ----------------------------------------------------------------------
      Select:
        begin
          // connect the address channel of the selected slave
          sel_awvalid      = buf_awvalid[sel];
          buf_awready[sel] = sel_awready;

          // if the selected port's address channel doesn't want access, move on to the next port.
          if (!sel_awvalid) begin
            select_new_port = 1;
          end else begin

            // if it does want access, then connect the data channel too
            sel_wvalid       = buf_wvalid[sel];
            buf_wready[sel]  = sel_wready;

            if (sel_awready) begin
              // the address channel is done, now check the data channel
              if (wr_burst_done) begin
                // check write response channel isn't blocking
                if (!(sel_bvalid & sel_bready)) begin
                  state_nxt = WaitRspChan;
                end else begin
                  // we're done with this burst, move on to the next port.
                  select_new_port = 1;
                end
              end else begin
                // wait for write channel to complete
                state_nxt = WaitWrChan;
              end
            end else begin
              // the address channel isn't ready, but is the write channel done?
              if (wr_burst_done) begin
                state_nxt = WaitAddrChan;
              end
            end
          end
        end
      // ----------------------------------------------------------------------
      WaitWrChan:
        begin
          // only connect the data channel of the selected slave
          sel_wvalid       = buf_wvalid[sel];
          buf_wready[sel]  = sel_wready;

          if (wr_burst_done) begin
            // make sure write response channel isn't blocking
            if (!(sel_bvalid & sel_bready)) begin
              state_nxt = WaitRspChan;
            end else begin
              select_new_port = 1;
              state_nxt       = Select;
            end
          end
        end
      // ----------------------------------------------------------------------
      WaitAddrChan:
        begin
          // only connect the address channel of the selected slave
          sel_awvalid      = buf_awvalid[sel];
          buf_awready[sel] = sel_awready;

          if (sel_awvalid & sel_awready) begin
            // make sure write response channel isn't blocking
            if (!(sel_bvalid & sel_bready)) begin
              state_nxt = WaitRspChan;
            end else begin
              select_new_port = 1;
              state_nxt       = Select;
            end
          end
        end
      // ----------------------------------------------------------------------
      WaitRspChan:
        if (sel_bvalid & sel_bready) begin
          select_new_port = 1;
          state_nxt       = Select;
        end
    endcase

    // Grant access to whichever port is next in line and currently
    // requesting access. Grant vector is registered to ease timing.
    if (select_new_port) begin
      request   = buf_awvalid;
      grant_nxt = round_robin(request, grant);
    end
  end

  // State machine registers
  always @(posedge clk) begin
    if (rst) begin
      state <= Select;
      grant <= 1; // one-hot signal
    end else begin
      state  <= state_nxt;
      grant  <= grant_nxt;
    end
  end

  // -----------------------
  // Optional Output Buffer
  // -----------------------
  generate
    if (OutBuffer) begin: outbuf
      stream_buf_v #(
        .DataBits (LenBits + AddrBits))
      addr_obuf(
        .clk       (clk),
        .rst       (rst),
        .in_valid  (sel_awvalid),
        .in_ready  (sel_awready),
        .in_data   ({sel_awlen, sel_awaddr}),
        .out_valid (mst_awvalid),
        .out_ready (mst_awready),
        .out_data  ({mst_awlen, mst_awaddr})
      );
      stream_buf_v #(
        .DataBits (1 + DataBits/8 + DataBits))
      data_obuf(
        .clk       (clk),
        .rst       (rst),
        .in_valid  (sel_wvalid),
        .in_ready  (sel_wready),
        .in_data   ({sel_wlast, sel_wstrb, sel_wdata}),
        .out_valid (mst_wvalid),
        .out_ready (mst_wready),
        .out_data  ({mst_wlast, mst_wstrb, mst_wdata})
      );
    end else begin: no_outbuf
      assign mst_awvalid = sel_awvalid;
      assign mst_awlen   = sel_awlen;
      assign mst_awaddr  = sel_awaddr;
      assign sel_awready = mst_awready;
      //
      assign mst_wvalid  = sel_wvalid;
      assign mst_wlast   = sel_wlast;
      assign mst_wstrb   = sel_wstrb;
      assign mst_wdata   = sel_wdata;
      assign sel_wready  = mst_wready;
    end
  endgenerate

  // for now, not using a buffer on the response channel. If we need to
  // register the mst_bready signal, then use a stream_buf_r.
  assign sel_bvalid = mst_bvalid;
  assign sel_bresp  = mst_bresp;
  assign mst_bready = sel_bready;

  // hardwire additional axi signals
  assign slv_bid     = {Ports{4'b0}};

  assign mst_awid    = 4'b0;
  assign mst_awsize  = clog2(BytesPerWord);
  assign mst_awlock  = 1'b0;
  assign mst_awburst = 2'b01;

  assign mst_wid     = 4'b0;

endmodule
