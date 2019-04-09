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
// Stream Clock Crossing
// -----------------------------------------------------------------------------
// Moves a data stream *slowly* between clock domains, using just one set of
// registers in each clock domain, and without using a fifo.
//
// -----------------------------------------------------------------------------
module stream_clock_cross #(
  parameter DataBits = 8)
(
  input                 din_clk,
  input                 din_rst,
  output                din_ready,
  input                 din_valid,
  input [DataBits-1:0]  din_data,
  //
  input                 dout_clk,
  input                 dout_rst,
  input                 dout_ready,
  output                dout_valid,
  output [DataBits-1:0] dout_data
);

  // -------------------
  // Input Stream Buffer
  // -------------------
  wire                  ibuf_valid, ibuf_ready;
  wire [DataBits-1:0]   ibuf_data;

  stream_buf_v #(
    .DataBits (DataBits))
  ibuf(
    .clk      (din_clk),
    .rst      (din_rst),
    //
    .in_valid (din_valid),
    .in_ready (din_ready),
    .in_data  (din_data),
    //
    .out_valid(ibuf_valid),
    .out_ready(ibuf_ready),
    .out_data (ibuf_data));

  // ------------------
  // Input Side Control
  // ------------------
  localparam Idle      = 0,
             WaitReady = 1;

  reg       in_state, out_state;
  reg       valid_toggle,      ready_toggle;
  reg [2:0] valid_toggle_sync, ready_toggle_sync;

  always @(posedge din_clk) begin
    case (in_state)
      Idle:
        if (ibuf_valid) begin
          in_state     <= WaitReady;
          valid_toggle <= ~valid_toggle;
        end
      WaitReady:
        if (ibuf_ready) begin
          in_state <= Idle;
        end
    endcase

    // sync to this clock domain
    ready_toggle_sync <= {ready_toggle_sync, ready_toggle};

    if (din_rst) begin
      in_state          <= Idle;
      valid_toggle      <= 0;
      ready_toggle_sync <= 0;
    end
  end

  // detect rising/falling edge on ready toggle
  assign ibuf_ready = ready_toggle_sync[2] ^ ready_toggle_sync[1];

  // -------------------
  // Output Side Control
  // -------------------
  wire sync_valid, sync_ready;

  always @(posedge dout_clk) begin

    // sync to this clock domain
    valid_toggle_sync <= {valid_toggle_sync, valid_toggle};

    case (out_state)
      Idle:
        // detect rising/falling edge
        if (valid_toggle_sync[2] ^ valid_toggle_sync[1]) begin
          out_state  <= WaitReady;
        end
      WaitReady:
        if (sync_ready) begin
          ready_toggle <= ~ready_toggle;
          out_state    <= Idle;
        end
    endcase

    if (dout_rst) begin
      out_state         <= Idle;
      ready_toggle      <= 0;
      valid_toggle_sync <= 0;
    end
  end

  assign sync_valid = (out_state == WaitReady);

  // --------------------
  // Output Stream Buffer
  // --------------------
  stream_buf_v #(
    .DataBits (DataBits))
  obuf(
    .clk      (dout_clk),
    .rst      (dout_rst),
    //
    .in_valid (sync_valid),
    .in_ready (sync_ready),
    .in_data  (ibuf_data),
    //
    .out_valid(dout_valid),
    .out_ready(dout_ready),
    .out_data (dout_data));

endmodule
