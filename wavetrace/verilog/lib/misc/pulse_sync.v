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
// Pulse Synchronizer
// -----------------------------------------------------------------------------
// Moves a pulse from one clock domain to another. There must be at least two
// 'dout_clk' cycles between each pulse on the 'din_pulse' input.
//
// -----------------------------------------------------------------------------
module pulse_sync (
  input      din_rst,
  input      din_clk,
  input      din_pulse,
  //
  input      dout_rst,
  input      dout_clk,
  output reg dout_pulse
);

  // Toggle a register each time we see an incoming pulse
  reg in_tog;
  always @(posedge din_clk) begin
    in_tog <= (din_pulse) ? ~in_tog : in_tog;
    if (din_rst)
      in_tog <= 0;
  end

  // Synchronization registers and XOR to detect transitions
  reg [2:0] out_sync;
  always @(posedge dout_clk) begin
    out_sync   <= {out_sync, in_tog};
    dout_pulse <= out_sync[2] ^ out_sync[1];
    if (dout_rst) begin
      out_sync   <= 0;
      dout_pulse <= 0;
    end
  end

endmodule
