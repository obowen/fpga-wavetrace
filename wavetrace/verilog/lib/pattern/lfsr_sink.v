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
// LFSR Sink
// -----------------------------------------------------------------------------
// Acts as a sink for data frames and compares the data against an expected LFSR
// generated pseudo random pattern. The number of bit errors occuring in each
// frame are counted and made available via APB registers. A register can select
// between expecting an LFSR pattern, a counter sequence, constants ones, or
// constant zeros.
//
// -----------------------------------------------------------------------------
module lfsr_sink #(
  parameter DataBits       = 8,
  parameter RepeatDefault  = 0,
  parameter PatternDefault = 0,
  parameter CountBits      = 32,
  parameter LfsrSeed       = 17'h15555)
(
  //
  input                 cfg_rst,
  input                 cfg_clk,
  input [4:0]           cfg_paddr,
  input                 cfg_pwrite,
  input [31:0]          cfg_pwdata,
  input                 cfg_psel,
  input                 cfg_penable,
  output                cfg_pready,
  output reg [31:0]     cfg_prdata,
  output                cfg_pslverr,
  //
  input                 din_clk,
  input                 din_rst,
  input                 din_valid,
  output                din_ready,
  input [DataBits-1:0]  din_data,
  input                 din_eof
);
`include "util.vh"

  // -----------
  // Address Map
  // -----------
  localparam  RxCountAddr    = 0, // RO: counts received data elements (valid when stable)
              ErrCountAddr   = 1, // RO: counts number of erros (valid when stable)
              ClrAddr        = 2, // RW: clears the counters and resets the lfsr
              RepeatAddr     = 3, // RW: if '1' the same sequence is expected each frame
              PatternAddr    = 4; // RW: 0 = LFSR, 1 = counter, 2 = ones, 3 = zeros

  // -------------
  // APB Interface
  // -------------
  assign cfg_pready  = 1;   // APB slave is always ready
  assign cfg_pslverr = 0;   // unused

  reg [CountBits-1:0] rx_count, rx_count_r, rx_count_rr;
  reg [CountBits-1:0] err_count, err_count_r, err_count_rr;
  reg                 cfg_clr, cfg_repeat;
  reg [1:0]           cfg_pattern;

  always @(posedge cfg_clk) begin :cfg
    integer   addr_i;
    addr_i = cfg_paddr >> 2; // convert to word address

    if (cfg_psel && !cfg_penable) begin

      // register writing
      if (cfg_pwrite) begin
        case (addr_i)
          ClrAddr:     cfg_clr    <= cfg_pwdata[0];
          RepeatAddr:  cfg_repeat <= cfg_pwdata[0];
          PatternAddr:   cfg_pattern <= cfg_pwdata;
        endcase

      // register reading
      end else begin
        case (addr_i)
          RxCountAddr:  cfg_prdata <= rx_count_rr;
          ErrCountAddr: cfg_prdata <= err_count_rr;
          ClrAddr:      cfg_prdata <= cfg_clr;
          RepeatAddr:   cfg_prdata <= cfg_repeat;
          PatternAddr:  cfg_prdata <= cfg_pattern;
        endcase
      end
    end

    // syncrhonization regs
    // *not* proper clock crossing, only reliable when counts are stable
    {rx_count_rr, rx_count_r}   <= {rx_count_r, rx_count};
    {err_count_rr, err_count_r} <= {err_count_r, err_count};

    if (cfg_rst) begin
      {rx_count_rr, rx_count_r}   <= 0;
      {err_count_rr, err_count_r} <= 0;
      cfg_clr                     <= 0;
      cfg_repeat                  <= RepeatDefault;
      cfg_pattern                 <= PatternDefault;
    end
  end

  // ---------
  // Sink Data
  // ---------
  localparam SumLatency = 1 + clog2(DataBits) - 2;

  wire [DataBits-1:0]      pattern_data;
  reg                      clr_r, clr_rr;
  reg                      repeat_r, repeat_rr;
  reg [SumLatency:0]       valid_pipe;
  reg [DataBits-1:0]       errs_xor;
  wire [clog2(DataBits+1)-1:0] errs;

  assign din_ready = 1;  // this block is always ready

  // count error bits using multiple pipeline stages
  sum_bits #(
    .InBits(DataBits))
  sum_errs (
    .clk  (din_clk),
    .en   (1'b1),
    .bits (errs_xor),
    .sum  (errs));

  always @(posedge din_clk) begin

    // clock domain synchronization
    {clr_rr, clr_r}       <= {clr_r, cfg_clr};
    {repeat_rr, repeat_r} <= {repeat_r, cfg_repeat};

    // compare incoming data to the value of our lfsr
    if (din_valid) begin
      errs_xor <= din_data ^ pattern_data;
    end

    // delay valid for latency of sum-bits module
    valid_pipe <= {valid_pipe, din_valid};

    if (valid_pipe[SumLatency]) begin
      err_count <= err_count + errs;
      rx_count  <= rx_count + 1;
    end

    if (clr_rr) begin
      rx_count   <= 0;
      err_count  <= 0;
    end

    if (din_rst) begin
      rx_count   <= 0;
      err_count  <= 0;
      {clr_rr, clr_r} <= 0;
    end

  end

  // ------------
  // LFSR Shifter
  // ------------
  wire                lfsr_shift, lfsr_init;
  wire [DataBits-1:0] lfsr_data;

  lfsr17_shift #(
    .DataBits (DataBits),
    .LfsrSeed (LfsrSeed))
  lfsr (
    .clk       (din_clk),
    .rst       (din_rst | clr_rr),
    .seed      (LfsrSeed),
    .init      (lfsr_init),
    .shift     (lfsr_shift),
    .lfsr_data (lfsr_data)
    );

  // re-initialize the LFSR at eof if in 'repeat' mode
  assign lfsr_init  = din_valid & din_eof & repeat_rr;

  // shift the LFSR after each received word
  assign lfsr_shift = din_valid;

  // -----------------
  // Pattern Selection
  // -----------------
  reg [DataBits-1:0] count_data;
  always @(posedge din_clk) begin
    if (din_valid) begin
      count_data <= (din_eof & repeat_rr) ? 0 : count_data + 1;
    end
    if (din_rst | clr_rr) begin
      count_data <= 0;
    end
  end

  assign pattern_data = (cfg_pattern == 0) ? lfsr_data        :
                        (cfg_pattern == 1) ? count_data       :
                        (cfg_pattern == 2) ? {DataBits{1'b1}} : 0;
endmodule
