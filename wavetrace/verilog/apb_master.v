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
// ---------------------------------------------------------------------------------
// APB Instruction Master
// ---------------------------------------------------------------------------------
// Receives a stream of data, extracts read/write instructions, and executes these
// over an APB interface. Read data is returned over an outgoing stream interface.
//
// A write command consists of three consecutive 32-bit data elements, beginning
// with 0xABCD0000, and a read burst command consists of two consecutive 32-bit
// elements beginning with 0xABCD00[nn], where 'nn' is an 8-bit burst size.
//
//  Write Command:       0xABCDA000 [ADDR] [DATA]
//  Read Command:        0xABCDB001 [ADDR]
//  Read Burst Command:  0xABCDB0nn [ADDR]         (where 'nn' is the burst size)
//
// ---------------------------------------------------------------------------------
module apb_master
(
  input             clk,
  input             rst,
  //
  input             din_valid,
  output reg        din_ready,
  input [31:0]      din_data,
  //
  output reg        dout_valid,
  output reg [31:0] dout_data,
  input             dout_ready,
  //
  output reg [31:0] mst_paddr,
  output reg        mst_pwrite,
  output reg [31:0] mst_pwdata,
  output reg        mst_psel,
  output reg        mst_penable,
  input             mst_pready,
  input [31:0]      mst_prdata,
  input             mst_pslverr
  );

`include "util.vh"

  // ------------------------
  // Instrction State Machine
  // ------------------------
  localparam Idle      = 0,
             WrAddr    = 1,
             WrData    = 2,
             WrEn      = 3,
             WrWait    = 4,
             RdAddr    = 5,
             RdEn      = 6,
             RdWait    = 7,
             RdData    = 8,
             NumStates = 9;

  localparam WrCmd  = 32'hABCDA000;
  localparam RdCmd  = 32'hABCDB001;

  reg [clog2(NumStates)-1:0] state;
  reg [7:0]                  burst_remain;

  always @(posedge clk) begin

    case (state)
      // ---------------------------------
      Idle:
        if (din_valid & din_ready) begin
          if (din_data == WrCmd) begin
            state <= WrAddr;
          end else if (din_data[31:8] == RdCmd[31:8] && din_data[7:0] > 0) begin
            state        <= RdAddr;
            burst_remain <= din_data[7:0];
          end
        end
      // ---------------------------------
      WrAddr:
        if (din_valid & din_ready) begin
          mst_paddr <= din_data;
          state     <= WrData;
        end
      // ---------------------------------
      WrData:
        if (din_valid & din_ready) begin
          mst_pwdata <= din_data;
          mst_pwrite <= 1;
          mst_psel   <= 1;
          din_ready  <= 0;
          state      <= WrEn;
        end
      // ---------------------------------
      WrEn:
        begin
          mst_penable <= 1;
          state       <= WrWait;
        end
      // ---------------------------------
      WrWait:
        if (mst_pready) begin
          mst_penable <= 0;
          mst_psel    <= 0;
          din_ready   <= 1;
          state       <= Idle;
        end
      // ---------------------------------
      RdAddr:
        if (din_valid & din_ready) begin
          mst_paddr  <= din_data;
          mst_pwrite <= 0;
          mst_psel   <= 1;
          din_ready  <= 0;
          state      <= RdEn;
        end
      // ---------------------------------
      RdEn:
        begin
          mst_penable <= 1;
          state       <= RdWait;
        end
      // ---------------------------------
      RdWait:
        if (mst_pready) begin
          mst_penable  <= 0;
          mst_psel     <= 0;
          dout_data    <= mst_prdata;
          dout_valid   <= 1;
          state        <= RdData;
          burst_remain <= burst_remain - 1;
        end
      // ----------------------------------
      RdData:
        if (dout_ready) begin
          dout_valid <= 0;
          if (burst_remain == 0) begin
            din_ready <= 1;
            state     <= Idle;
          end else begin
            mst_paddr <= mst_paddr + 4;
            mst_psel  <= 1;
            state     <= RdEn;
          end
        end
    endcase

    if (rst) begin
      state       <= Idle;
      din_ready   <= 1;
      dout_valid  <= 0;
      mst_pwrite  <= 0;
      mst_psel    <= 0;
      mst_penable <= 0;
    end
  end

endmodule
