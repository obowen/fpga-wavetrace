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
// --------------------------------------------------------------------------
// Stream Stats
// --------------------------------------------------------------------------
// Monitors a stream and counts the number of valid transactions and frames.
//
// --------------------------------------------------------------------------
module stream_stats #(
  parameter DataBits = 8)
(
  input                 clk,
  input                 rst,
  //
  input [4:0]           cfg_paddr,
  input                 cfg_psel,
  input                 cfg_penable,
  input                 cfg_pwrite,
  input [31:0]          cfg_pwdata,
  output                cfg_pready,
  output reg [31:0]     cfg_prdata,
  output                cfg_pslverr,
  //
  input                 din_ready,
  input                 din_valid,
  input [DataBits-1:0]  din_data,
  input                 din_eof
);

  // -----------
  // Address Map
  // -----------
  localparam StatusAddr    = 0, // RO: Stream Status
             VldCntAddr    = 1, // RW: Counts number of valid transactions
             FrameCntAddr  = 2, // RW: Counts number of frames
             RdyLowCntAddr = 3; // RW: Counts number of cycles ready has been low

  assign cfg_pready  = 1;   // APB slave is always ready
  assign cfg_pslverr = 0;   // unused

  reg [31:0] valid_count, frame_count, rdy_low_count;

  always @(posedge clk) begin :cfg
    integer addr_i;
    addr_i = cfg_paddr >> 2; // convert to word address

    // --------------
    // Monitor Stream
    // --------------
    if (din_valid & din_ready) begin
      valid_count <= valid_count + 1;
    end

    if (din_valid & din_ready & din_eof) begin
      frame_count <= frame_count + 1;
    end

    if (~din_ready) begin
      rdy_low_count <= rdy_low_count + 1;
    end

    // --------------
    // APB Registers
    // --------------
    if (cfg_psel && !cfg_penable) begin
      // register writing
      if (cfg_pwrite) begin
        case (addr_i)
          VldCntAddr:    valid_count   <= cfg_pwdata;
          FrameCntAddr:  frame_count   <= cfg_pwdata;
          RdyLowCntAddr: rdy_low_count <= cfg_pwdata;
        endcase
      // register reading
      end else begin
        case (addr_i)
          StatusAddr:    cfg_prdata <= {din_ready, din_valid};
          VldCntAddr:    cfg_prdata <= valid_count;
          FrameCntAddr:  cfg_prdata <= frame_count;
          RdyLowCntAddr: cfg_prdata <= rdy_low_count;
        endcase
      end
    end

    if (rst) begin
      valid_count   <= 0;
      frame_count   <= 0;
      rdy_low_count <= 0;
    end

  end

endmodule
