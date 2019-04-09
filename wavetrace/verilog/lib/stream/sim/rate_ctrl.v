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
// Rate Control
// -----------------------------------------------------------------------------
// Randomly drives an 'active' output signal high or low. This can be used
// to conrtol the flow rate of a stream source or a stream sink. Once high,
// 'active' will be held high until the ack input is asserted.
//
// The probability that 'active' will be high is ramped up and down between the
// 'MinThroughput' and 'MaxThroughput' parameters. The period of the ramp
// function is specified in terms of clock cycles using the 'Period' parameter.
// The probability of being active follows a waveform which is divided into four
// segments: ramp-up, hold-high, ramp-down, and hold-low.
//
//   MaxThroughput ........_____........._____......
//                        /     \       /     \
//   MinThroughpuyt ...../       \_____/       \____
//                       |<---Period-->|
//
// -----------------------------------------------------------------------------
module rate_ctrl #(
  parameter real MinThroughput = 0,    // Minimum probability of being active
  parameter real MaxThroughput = 100,  // Maximum probability of being active
  parameter      Period        = 1000, // Period of active ramp-up/down waveform
  parameter      Seed          = 1)    // Seed for initializing random numbers
(
  input      clk,
  input      rst,
  output reg active,
  input      ack
);

  // -----------------------------
  // Initaizlie Random Number Seed
  // -----------------------------
  integer  seed_i;
  initial begin
    seed_i = Seed;
  end

  // ------------------------
  // Generate Active Waveform
  // ------------------------
  // Calculate the slope of the ramp-up and ramp-down segments of the waveform
  localparam real Slope = (MaxThroughput - MinThroughput) / ($itor(Period) / 4);

  localparam RampUp   = 0,
             HoldHigh = 1,
             RampDown = 2,
             HoldLow  = 3;

  reg [1:0] state;
  real      rate, delta;
  integer   rnd, count;
  always @(posedge clk) begin
    if (rst) begin
      count  <= 0;
      state  <= RampUp;
      rate   <= MinThroughput;
      active <= 0;
    end else begin

      // move on to the next waveform state every 1/4 period
      if (count == Period/4 - 1) begin
        state <= (state == HoldLow) ? RampUp : state + 1;
        count <= 0;
      end else begin
        count <= count + 1;
      end

      // adjust the current output rate
      delta = (state == RampUp)   ?  Slope:
              (state == RampDown) ? -Slope : 0;
      rate <= rate + delta;

      // randomly assert active with probability specified by the current rate
      if (!active || ack) begin
        rnd     = $unsigned($random(seed_i)) % 100;
        active <= (rnd < rate) ? 1 : 0;
      end
    end
  end

endmodule
