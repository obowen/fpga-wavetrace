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
// LFSR Throttle
// -----------------------------------------------------------------------------
// Throttles the rate of flow of a valid/ready stream. An LFSR pseudo random
// number is compared against a configurable rate register to determine when
// to pass or stall the stream.
//
// -----------------------------------------------------------------------------
module lfsr_throttle #(
  parameter Seed = 1,
  parameter RateDefault = 128)  // Probabiliy of passing stream
                                // (0 = 0%, 127 = 50%, 255 = 100%)
(
  input             cfg_clk,
  input             cfg_rst,
  input [4:0]       cfg_paddr,
  input             cfg_pwrite,
  input [31:0]      cfg_pwdata,
  input             cfg_psel,
  input             cfg_penable,
  output            cfg_pready,
  output reg [31:0] cfg_prdata,
  output            cfg_pslverr,
  //
  input             data_clk,
  input             data_rst,
  input             din_valid,
  output            din_ready,
  output            dout_valid,
  input             dout_ready
  );

  // -----------
  // Address Map
  // -----------
  localparam StatusAddr = 0, // RO: status of stream inputs / outputs
             RateAddr   = 1; // RW: rate of data throughput, 0 to 255

  // -------------
  // APB Interface
  // -------------
  assign cfg_pready  = 1;   // APB slave is always ready
  assign cfg_pslverr = 0;   // unused

  reg [7:0]           cfg_rate;

  always @(posedge cfg_clk) begin :cfg
    integer addr_i;
    addr_i = cfg_paddr >> 2; // convert to word address

    if (cfg_psel && !cfg_penable) begin

      // register writing
      if (cfg_pwrite) begin
        case (addr_i)
          RateAddr:     cfg_rate <= cfg_pwdata;
        endcase

      // register reading
      end else begin
        case (addr_i)
          StatusAddr:   cfg_prdata <= {dout_ready, dout_valid,
                                       din_ready,  din_valid};
          RateAddr:     cfg_prdata <= cfg_rate;
        endcase
      end
    end

    if (cfg_rst) begin
      cfg_rate <= RateDefault;
    end
  end

  // ------------
  // LFSR Shifter
  // ------------
  wire       lfsr_en;
  wire [7:0] lfsr_data;
  reg        active;

  lfsr15_shift #(
    .DataBits (8),
    .LfsrSeed (Seed))
  lfsr (
    .clk       (data_clk),
    .rst       (data_rst),
    .seed      (Seed),
    .init      (1'b0),
    .shift     (lfsr_en),
    .lfsr_data (lfsr_data)
    );

  assign lfsr_en = (!active || (din_valid & din_ready));

  // ---------------
  // Throttle Stream
  // ---------------
  reg [7:0]  rate_r, rate_rr;

  always @(posedge data_clk) begin

    // sync to this clock domain (not proper clock crossing,
    // may be incorrect if rates are changed during data flow)
    {rate_rr, rate_r}  <= {rate_r, cfg_rate};

    // randomly toggle active state with a probability specified by rate
    if (lfsr_en) begin
      if (rate_rr == 0) begin
        active <= 0;
      end else begin
        active <= (lfsr_data[7:0] <= rate_rr) ? 1 : 0;
      end
    end

    if (data_rst) begin
      active  <= 0;
      rate_r  <= RateDefault;
      rate_rr <= RateDefault;
    end
  end

  assign dout_valid = (active) ? din_valid  : 0;
  assign din_ready  = (active) ? dout_ready : 0;

endmodule
