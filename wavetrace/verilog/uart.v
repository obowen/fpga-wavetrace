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
// ------------------------------------------------------------------------------
// Uart
// ------------------------------------------------------------------------------
// Implements a clock-divider based Uart with a parameterizable baudrate, one
// start and stop bit, no parity bits, and no flow control.
//
// Example uart waveform:
// _________      ____                ____                ____
//          |____|    |____|____|____|    |____|____|____|    |____|
//            ST   0    1    2    3    4    5    6    7    SP   ST
//
// ------------------------------------------------------------------------------
module uart #(
  parameter ClockHz = 80000000,
  parameter Baud    = 115200)
(
  input            clk,
  input            rst,
  //
  input            uart_rx,
  output reg       uart_tx,
  //
  input            din_valid,
  output           din_ready,
  input [7:0]      din_data,
  //
  output reg       dout_valid,
  input            dout_ready,
  output reg [7:0] dout_data
);

`include "util.vh"

  localparam Period      = ClockHz / Baud,
             HalfPeriod  = Period / 2;

  localparam Idle    = 0,
             Active  = 1,
             Error   = 2;

  reg [1:0]                rx_state;
  reg                      rx_sync, uart_rx_d;
  reg [clog2(Period)-1:0]  rx_divider;
  reg [3:0]                rx_count;
  reg [7:0]                rx_data;
  reg                      rx_valid;
  //
  reg [1:0]                tx_state;
  reg [3:0]                tx_count;
  reg [clog2(Period)-1:0]  tx_divider;
  reg [7:0]                tx_data;

  always @(posedge clk) begin

    // sync uart rx to this clock
    {rx_sync, uart_rx_d} <= {uart_rx_d, uart_rx};

    // defaults
    rx_valid <= 0;

    // ---------------------
    // Receive State Machine
    // ---------------------
    case (rx_state)
      // -------------------------------------
      Idle:
        // wait for the start bit
        if (!rx_sync) begin
          rx_divider <= rx_divider + 1;
          if (rx_divider == HalfPeriod-1) begin
            rx_count   <= 0;
            rx_divider <= 0;
            rx_state   <= Active;
          end
        end else begin
          // restart the counter if the rx line goes high
          rx_divider <= 0;
        end
      // -------------------------------------
      Active:
        if (rx_divider == Period-1) begin
          // shift in the rx data, lsb first
          rx_data    <= {rx_sync, rx_data[7:1]};
          rx_divider <= 0;
          rx_count   <= rx_count + 1;
          if (rx_count == 7) begin
            // done with this byte
            rx_valid <= 1;
          end else if (rx_count == 8) begin
            // should get a '1' for stop bit
            rx_state <= (rx_sync) ? Idle : Error;
          end
        end else begin
          rx_divider <= rx_divider + 1;
        end
      // -------------------------------------
      Error:
        // wait until rx line goes high again
        if (rx_sync) begin
          rx_state <= Idle;
        end
    endcase

    // buffer to hold one byte of received data
    if (rx_valid) begin
      dout_data  <= rx_data;
    end

    if (rx_valid) begin
      dout_valid <= 1;
    end else if (dout_ready) begin
      dout_valid <= 0;
    end


    // ----------------------
    // Transmit State Machine
    // ----------------------
    case (tx_state)
      // -----------------------------------------
      Idle:
        if (din_valid) begin
          // latch data and generate start bit
          tx_data    <= din_data;
          uart_tx    <= 0;
          tx_count   <= 0;
          tx_divider <= 0;
          tx_state   <= Active;
        end
      // -----------------------------------------
      Active:
        if (tx_divider == Period-1) begin
          tx_divider <= 0;
          tx_count   <= tx_count + 1;
          if (tx_count == 9) begin
            // done with byte
            tx_state   <= Idle;
          end else if (tx_count == 8) begin
            // generate stop bit
            uart_tx    <= 1;
          end else begin
            // shift out transmit data
            {tx_data, uart_tx} <= tx_data;
          end
        end else begin
          tx_divider <= tx_divider + 1;
        end
      // -----------------------------------------
    endcase

    if (rst) begin
      rx_state   <= Idle;
      tx_state   <= Idle;
      uart_tx    <= 1;
      rx_valid   <= 0;
      dout_valid <= 0;
    end
  end

  assign din_ready = (tx_state == Idle);

endmodule


