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
// APB Demux
// -----------------------------------------------------------------------------
// Allows a single APB master to communicate with multiple APB slaves. This block
// uses the upper bits of the address bus to select the slave.
//
// -----------------------------------------------------------------------------
module apb_demux #(
  parameter NumPorts = 2,
  parameter AddrBits = 32)
(
  input                        clk,
  input                        rst,
  //
  input [AddrBits-1:0]         slv_paddr,
  input                        slv_psel,
  input                        slv_penable,
  output                       slv_pready,
  output [31:0]                slv_prdata,
  output                       slv_pslverr,
  //
  output reg [NumPorts-1:0]    mst_psel,
  output reg [NumPorts-1:0]    mst_penable,
  input      [NumPorts-1:0]    mst_pready,
  input      [NumPorts*32-1:0] mst_prdata,
  input      [NumPorts-1:0]    mst_pslverr
);
`include "util.vh"

  localparam PortBits = clog2(NumPorts);

  // Use MSBs for port selection
  wire [PortBits-1:0] sel = slv_paddr[AddrBits-1 -: PortBits];

  // demux for the control signals
  always @(*) begin
    mst_psel          = 0;
    mst_penable       = 0;
    mst_psel[sel]     = slv_psel;
    mst_penable[sel]  = slv_penable;
  end

  // mux for the return signals
  assign slv_prdata  = mst_prdata[sel*32 +: 32];
  assign slv_pready  = mst_pready[sel];
  assign slv_pslverr = mst_pslverr[sel];

endmodule
