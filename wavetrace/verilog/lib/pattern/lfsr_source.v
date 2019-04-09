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
// LFSR Source
// -----------------------------------------------------------------------------
// Generates frames containing an LFSR based pseudo random data pattern. The
// 'go' register starts or stops the data generation and takes effect on frame
// boundaries. The 'repeat' register determines if the same sequence is sent for
// each frame. A register can select between the LFSR pattern, a counter
// sequence, constants ones, or constant zeros.
//
// -----------------------------------------------------------------------------
module lfsr_source #(
  parameter DataBits       = 8,
  parameter GoDefault      = 0,
  parameter RepeatDefault  = 0,
  parameter PatternDefault = 0,
  parameter GapDefault     = 0,
  parameter CountBits      = 32,
  parameter MaxLength      = 1024,
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
  input                 dout_clk,
  input                 dout_rst,
  output                dout_valid,
  input                 dout_ready,
  output [DataBits-1:0] dout_data,
  output                dout_eof
);

`include "util.vh"

  // -----------
  // Address Map
  // -----------
  localparam
    GoAddr       = 0, // RW: starts data generation
    TxCountAddr  = 1, // RO: counts transmitted data elements (valid when stable)
    ClrAddr      = 2, // RW: clears the counters and resets the lfsr
    RepeatAddr   = 3, // RW: if '1' the same sequence is sent each frame
    LengthAddr   = 4, // RW: sets length of each frame, default is MaxLength,
                      //     mininum length is 2 words
    PatternAddr  = 5, // RW: 0 = LFSR, 1 = counter, 2 = ones, 3 = zeros
    GapAddr      = 6; // RW: size of gap between frames (in words)

  // -------------
  // APB Interface
  // -------------
  assign cfg_pready  = 1;   // APB slave is always ready
  assign cfg_pslverr = 0;   // unused

  reg                          cfg_go, cfg_clr, cfg_repeat;
  reg [clog2(MaxLength+1)-1:0] cfg_len;
  reg [1:0]                    cfg_pattern;
  reg [CountBits-1:0]          tx_count, tx_count_r, tx_count_rr;
  reg [31:0]                   cfg_gap;

  always @(posedge cfg_clk) begin :cfg
    integer addr_i;
    addr_i = cfg_paddr >> 2; // convert to word address

    if (cfg_psel && !cfg_penable) begin

      // register writing
      if (cfg_pwrite) begin
        case (addr_i)
          GoAddr:        cfg_go      <= cfg_pwdata[0];
          ClrAddr:       cfg_clr     <= cfg_pwdata[0];
          RepeatAddr:    cfg_repeat  <= cfg_pwdata[0];
          LengthAddr:    cfg_len     <= cfg_pwdata;
          PatternAddr:   cfg_pattern <= cfg_pwdata;
          GapAddr:       cfg_gap     <= cfg_pwdata;
        endcase

      // register reading
      end else begin
        case (addr_i)
          GoAddr:         cfg_prdata <= cfg_go;
          TxCountAddr:    cfg_prdata <= tx_count_rr;
          ClrAddr:        cfg_prdata <= cfg_clr;
          RepeatAddr:     cfg_prdata <= cfg_repeat;
          LengthAddr:     cfg_prdata <= cfg_len;
          PatternAddr:    cfg_prdata <= cfg_pattern;
          GapAddr:        cfg_prdata <= cfg_gap;
        endcase
      end
    end

    // syncrhonization regs
    // *not* proper clock crossing, only reliable when count is stable
    {tx_count_rr, tx_count_r} <= {tx_count_r, tx_count};

    if (cfg_rst) begin
      cfg_clr                    <= 0;
      cfg_go                     <= GoDefault;
      cfg_repeat                 <= RepeatDefault;
      cfg_len                    <= MaxLength;
      cfg_pattern                <= PatternDefault;
      cfg_gap                    <= GapDefault;
      {tx_count_rr, tx_count_r}  <= 0;
    end
  end

  // ----------------
  // Frame Generation
  // ----------------
  localparam Idle   = 0,
             Active = 1,
             Gap    = 2;

  reg [1:0]                  state;
  reg [31:0]                 len_count;
  reg                        go_r, go_rr;
  reg                        clr_r, clr_rr;
  reg                        repeat_r, repeat_rr;
  reg                        gen_valid, gen_eof;
  wire                       gen_ready;
  wire [DataBits-1:0]        gen_data;

  always @(posedge dout_clk) begin

    // clock domain synchronization for 1-bit regs
    // NOTE: length and gap do not have clock crossing registers,
    //       these should be kept stable during traffic generation.
    {go_rr,  go_r}        <= {go_r, cfg_go};
    {clr_rr, clr_r}       <= {clr_r, cfg_clr};
    {repeat_rr, repeat_r} <= {repeat_r, cfg_repeat};

    case (state)
      // ---------------------------------------------
      Idle:
        if (go_rr) begin
          state     <= Active;
          gen_valid <= 1;
        end
      // ---------------------------------------------
      Active:
        if (gen_ready) begin
          tx_count  <= tx_count + 1;
          gen_eof   <= (len_count == cfg_len-2);
          len_count <= (gen_eof) ? 0 : len_count + 1;
          // at eof, check if we need to insert a gap, or stop traffic
          if (gen_eof && (!cfg_go || cfg_gap > 0)) begin
            gen_valid <= 0;
            state     <= (cfg_gap > 0) ? Gap : Idle;
          end
        end
      // ---------------------------------------------
      Gap:
        // handle case where gap gets set to zero while we're in this state
        if (len_count == cfg_gap - 1 || cfg_gap == 0) begin
          len_count <= 0;
          if (cfg_go) begin
            state     <= Active;
            gen_valid <= 1;
          end else begin
            state <= Idle;
          end
        end else begin
          len_count <= len_count + 1;
        end
    endcase

    if (dout_rst | clr_rr) begin
      state      <= Idle;
      gen_valid  <= 0;
      gen_eof    <= 0;
      len_count  <= 0;
      tx_count   <= 0;
    end
  end

  // ------------
  // LFSR Shifter
  // ------------
  wire                lfsr_en, lfsr_init;
  wire [DataBits-1:0] lfsr_data;

  lfsr17_shift #(
    .DataBits (DataBits),
    .LfsrSeed (LfsrSeed))
  lfsr (
    .clk       (dout_clk),
    .rst       (dout_rst | clr_rr),
    .seed      (LfsrSeed),
    .init      (lfsr_init),
    .shift     (lfsr_en),
    .lfsr_data (lfsr_data)
    );

  // re-initialize the LFSR at eof if in 'repeat' mode
  assign lfsr_init  = gen_valid & gen_ready & gen_eof & repeat_rr;

  // shift the LFSR value on each data transaction
  assign lfsr_en = gen_valid & gen_ready;

  // -----------------
  // Pattern Selection
  // -----------------
  reg [DataBits-1:0] count_data;
  always @(posedge dout_clk) begin
    if (gen_valid & gen_ready) begin
      count_data <= (gen_eof & repeat_rr) ? 0 : count_data + 1;
    end
    if (dout_rst | clr_rr) begin
      count_data <= 0;
    end
  end

  assign gen_data = (cfg_pattern == 0) ? lfsr_data        :
                    (cfg_pattern == 1) ? count_data       :
                    (cfg_pattern == 2) ? {DataBits{1'b1}} : 0;

  // ---------------------------------
  // Stream Buffer to register output
  // ---------------------------------
  stream_buf_v #(
    .DataBits(DataBits+1))
  obuf (
    .clk       (dout_clk),
    .rst       (dout_rst),
    .in_valid  (gen_valid),
    .in_ready  (gen_ready),
    .in_data   ({gen_eof, gen_data}),
    .out_valid (dout_valid),
    .out_ready (dout_ready),
    .out_data  ({dout_eof, dout_data}));

endmodule
