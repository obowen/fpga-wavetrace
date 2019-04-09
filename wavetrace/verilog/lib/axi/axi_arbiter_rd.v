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
// AXI Arbiter for Read Channels
// --------------------------------------------------------------------------------------
// Uses round robin scheduling to share the read channels of a single AXI slave with
// multiple AXI masters. This block supports pending reads from multiple masters.
//
// NOTE: This block does not support out-of-order reads, locking, or any atypical burst
//       requests. The 'rid', 'arsize', 'arburst', and 'arlock' outputs are constant.
//
// Optional Input and output buffers can be instantiated to improve timing, these
// will increase latency through the arbiter, but will not introduce any wait states.
//
// NOTE: The slave-ports ready signals won't necessarily be high by default if
//       the input buffers are not used.
//
// --------------------------------------------------------------------------------------
module axi_arbiter_rd #(
  parameter Ports           = 2,       // Number of AXI slave ports
            DataBits        = 64,      // Width of AXI data bus
            AddrBits        = 32,      // Width of AXI slave bus
            LenBits         = 4,       // Width of AXI burst length signals
            NumPendingReads = 6,       // Maximum number of pending read instructions
            InBuffers       = 0,       // Determines if input  buffer will be instantiated
            OutBuffer       = 1)       // Determines if output buffer will be instantiated
(
  input                            clk,
  input                            rst,
  // AXI Slave Ports: Read Address Channels
  input      [Ports-1:0]           slv_arvalid,
  output     [Ports-1:0]           slv_arready,
  input      [Ports*AddrBits-1:0]  slv_araddr,
  input      [Ports*LenBits-1:0]   slv_arlen,
  // AXI Slave Ports: Read Data Channels
  output reg [Ports-1:0]           slv_rvalid,
  input      [Ports-1:0]           slv_rready,
  output reg [Ports*DataBits-1:0]  slv_rdata,
  output reg [Ports*2-1:0]         slv_rresp,
  output reg [Ports-1:0]           slv_rlast,
  output     [Ports*4-1:0]         slv_rid,    // tied to '0000'
  // AXI Master Port: Read Address Channel
  output                           mst_arvalid,
  input                            mst_arready,
  output     [AddrBits-1:0]        mst_araddr,
  output     [LenBits-1:0]         mst_arlen,
  output     [3:0]                 mst_arid,    // tied to '0000'
  output     [2:0]                 mst_arsize,  // indicates bytes per word
  output     [1:0]                 mst_arburst, // tied to '01'
  output     [1:0]                 mst_arlock,  // tied to '00'
  // Master Port: Read Data Channel
  input                            mst_rvalid,
  output reg                       mst_rready,
  input      [3:0]                 mst_rid,     // ignored
  input      [DataBits-1:0]        mst_rdata,
  input      [1:0]                 mst_rresp,
  input                            mst_rlast);

`include "util.vh"
`include "axi_arbiter.vh"

  localparam BytesPerWord = DataBits / 8;

  // -----------------------
  // Optional Input Buffers
  // -----------------------
  wire [Ports-1:0]      buf_arvalid;
  reg  [Ports-1:0]      buf_arready;
	wire [AddrBits-1:0]   buf_araddr[0:Ports-1];
  wire [LenBits-1:0]    buf_arlen [0:Ports-1];

  genvar n;
  generate
    for (n=0; n < Ports; n=n+1) begin: inbufs
      if (InBuffers) begin: inbuf
        // TODO: probably need both "_r" and "_v" buffers, check timing
        stream_buf_r #(
          .DataBits (LenBits + AddrBits))
        rd_buf(
          .clk       (clk),
          .rst       (rst),
          .in_valid  (slv_arvalid[n]),
          .in_ready  (slv_arready[n]),
          .in_data   ({slv_arlen[n*LenBits +: LenBits],
                       slv_araddr[n*AddrBits +: AddrBits]}),
          .out_valid (buf_arvalid[n]),
          .out_ready (buf_arready[n]),
          .out_data  ({buf_arlen[n],
                       buf_araddr[n]})
        );

      end else begin: no_inbuf
        assign buf_arvalid[n] = slv_arvalid[n];
        assign buf_arlen[n]   = slv_arlen[n*LenBits +: LenBits];
        assign buf_araddr[n]  = slv_araddr[n*AddrBits +: AddrBits];
        assign slv_arready[n] = buf_arready[n];
      end
    end
  endgenerate

  // -----------------------------------
  // Read Channel Round Robin Scheduling
  // -----------------------------------
  reg [Ports-1:0]        grant, grant_nxt, request;
  reg [clog2(Ports)-1:0] sel;

  reg                    sel_arvalid;
  wire                   sel_arready;
  reg [AddrBits-1:0]     sel_araddr;
  reg [LenBits-1:0]      sel_arlen;

  always @(*) begin
    // default - keep granting access to the same port
    grant_nxt         = grant;

    // get index of currently selected slave
    sel               = onehot2bin(grant, Ports); // TODO: rename to index?

    // muxes to select one of the ports
    sel_arvalid       = buf_arvalid[sel];
    sel_araddr        = buf_araddr[sel];
    sel_arlen         = buf_arlen[sel];

    // pass back ready signal to the selected port
    buf_arready       = 0;
    buf_arready[sel]  = sel_arready;

    // if the selected port doesn't want access, or if the transaction is done,
    // select a new port.
    if (!sel_arvalid || sel_arready) begin
      request   = buf_arvalid;
      grant_nxt = round_robin(request, grant);
    end
  end

  // register grant signal, this is used as the starting point to figure out who
  // gets access next. This register also breaks up the combinatorial logic.
  always @(posedge clk) begin
    if (rst) grant <= 1; // one-hot signal
    else     grant <= grant_nxt;
  end

  // split the read-address stream between the output and the fifo
  // (this ensures we backpressure when the fifo is full)
  wire [1:0] split_valid, split_ready;
  stream_split split(
    .in_valid(sel_arvalid),
    .in_ready(sel_arready),
    .out_valid(split_valid),
    .out_ready(split_ready)
  );

  // ----------------------
  // Optional Output Buffer
  // ----------------------
  generate
    if (OutBuffer) begin: outbuf
    stream_buf_v #(
      .DataBits (LenBits + AddrBits))
    addr_obuf(
      .clk       (clk),
      .rst       (rst),
      .in_valid  (split_valid[0]),
      .in_ready  (split_ready[0]),
      .in_data   ({sel_arlen, sel_araddr}),
      .out_valid (mst_arvalid),
      .out_ready (mst_arready),
      .out_data  ({mst_arlen, mst_araddr})
    );
    end else begin: no_outbuf
      assign mst_arvalid    = split_valid[0];
      assign mst_arlen      = sel_arlen;
      assign mst_araddr     = sel_araddr;
      assign split_ready[0] = mst_arready;
    end
  endgenerate

  // --------------------------------
  // Small fifo to store read owners
  // --------------------------------
  // keep track of which master issued each read so we know who to return the data to
  wire                     fifo_valid;
  reg                      fifo_ready;
  wire [clog2(Ports)-1:0]  fifo_sel;

  stream_fifo_1clk_regs #(
    .Width    (clog2(Ports)),
    .Depth    (NumPendingReads))
  fifo(
    .rst       (rst),
    .clk       (clk),
    //
    .din_valid (split_valid[1]),
    .din_ready (split_ready[1]),
    .din_data  (sel),
    //
    .dout_valid(fifo_valid),
    .dout_ready(fifo_ready),
    .dout_data (fifo_sel),
    .used      ());

  // ----------------------------------------
  // Pass back read data to the selected port
  // ----------------------------------------
  always @(*) begin
    // default
    slv_rvalid           = 0;

    // merge fifo and read-data streams, but only pull data from the fifo at the end of each burst.
    slv_rvalid[fifo_sel] = mst_rvalid & fifo_valid;
    fifo_ready           = slv_rready[fifo_sel] & mst_rvalid & mst_rlast;
    mst_rready           = slv_rready[fifo_sel] & fifo_valid;

    // remaining signals get passed to all ports
    slv_rdata            = {Ports{mst_rdata}};
    slv_rresp            = {Ports{mst_rresp}};
    slv_rlast            = {Ports{mst_rlast}};
  end

  assign slv_rid     = {Ports{4'b0}};
  assign mst_arid    = 4'b0;
  assign mst_arsize  = clog2(BytesPerWord);
  assign mst_arlock  = 1'b0;
  assign mst_arburst = 2'b01;

endmodule
