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
// Frame Source
// -----------------------------------------------------------------------------
// Generates frames of configuratble length and with a configurable size 'gap'
// between frames. The data follows a counter patern, with an increasing
// increment each frame. At the end of each frame, an IRQ is asserted and a
// checksum for the previous frame is made avaialable via the APB interface.
// Frame generation starts when the 'go' register is high. If the 'go' register
// is set to low, generation will stop on the next frame boundary.
//
// ------------------------------------------------------------------------------
module frame_source #(
  parameter DataBits = 8,
  parameter GoDefault = 0)
(
  input                 clk,
  input                 rst,
  //
  input [5:0]           cfg_paddr,
  input                 cfg_pwrite,
  input [31:0]          cfg_pwdata,
  input                 cfg_psel,
  input                 cfg_penable,
  output                cfg_pready,
  output reg [31:0]     cfg_prdata,
  output                cfg_pslverr,
  output reg            cfg_irq,
  //
  output                dout_valid,
  input                 dout_ready,
  output [DataBits-1:0] dout_data,
  output                dout_eof
);

  // -------------
  //  Address Map
  // -------------
  localparam StatusAddr     = 0, // RO: Stream Status for debug, bit[0]=dout_valid, bit[1]=dout_ready
             FrameLenAddr   = 1, // RW: number of data elements per frame
             GapLenAddr     = 2, // RW: number of delay cycles between frames
             GoAddr         = 3, // RW: starts frame generation, repeats if left high
             ChecksumAddr   = 4, // RO: checksum of last sent frame
             PosCountAddr   = 5, // RO: position in the current frame
             FrameCountAddr = 6, // RO: number of frames generated
             CycleCountAddr = 7, // RW: free running cycle counter, can be used to calculate frame rate
             IrqAddr        = 8; // RW: irq register, latched at eof, write '0' to clear

  // --------------
  // APB Interface
  // --------------
  assign cfg_pready  = 1;   // APB slave is always ready
  assign cfg_pslverr = 0;   // unused

  reg        cfg_go;
  reg [15:0] cfg_frame_len, cfg_gap_len, pos;
  reg [15:0] frame_count, cycle_count;
  reg [31:0] checksum, checksum_r;
  wire       gen_valid, gen_ready, gen_eof;

  always @(posedge clk) begin :cfg
    integer addr_i;
    addr_i = cfg_paddr >> 2; // convert to word address

    // free running cycle counter
    cycle_count <= cycle_count + 1;

    if (cfg_psel && !cfg_penable) begin
      // register writing
      if (cfg_pwrite) begin
        case (addr_i)
          FrameLenAddr:   cfg_frame_len <= cfg_pwdata;
          GapLenAddr:     cfg_gap_len   <= cfg_pwdata;
          GoAddr:         cfg_go        <= cfg_pwdata[0];
          CycleCountAddr: cycle_count   <= cfg_pwdata;
          IrqAddr:        cfg_irq       <= cfg_pwdata[0];
        endcase

      // register reading
      end else begin
        case (addr_i)
          StatusAddr:     cfg_prdata <= {dout_ready, dout_valid};
          FrameLenAddr:   cfg_prdata <= cfg_frame_len;
          GapLenAddr:     cfg_prdata <= cfg_gap_len;
          GoAddr:         cfg_prdata <= cfg_go;
          ChecksumAddr:   cfg_prdata <= checksum_r;
          PosCountAddr:   cfg_prdata <= pos;
          FrameCountAddr: cfg_prdata <= frame_count;
          CycleCountAddr: cfg_prdata <= cycle_count;
          IrqAddr:        cfg_prdata <= cfg_irq;
        endcase
      end
    end

    // latch irq
    if (gen_valid & gen_ready & gen_eof)
      cfg_irq <= 1;

    if (rst) begin
      cfg_go         <= GoDefault;
      cfg_frame_len  <= 2230;
      cfg_gap_len    <= 100;
      cfg_irq        <= 0;
      cycle_count    <= 0;
    end
  end

  // -----------------
  // Frame Generation
  // -----------------
  localparam Idle   = 0,
             Active = 1,
             Gap    = 2;

  reg [2:0]          state;
  reg [DataBits-1:0] gen_data, incr;
  reg [15:0]         gap_count;
  reg [15:0]         frame_len_m1;

  always @(posedge clk) begin

    case (state)
      // ----------------------------------------
      Idle:
        if (cfg_go) begin
          state    <= Active;
          checksum <= 0;
          gen_data <= frame_count[DataBits-1:0];
          // register to ease timing
          frame_len_m1 <= cfg_frame_len - 1;
        end
      // ----------------------------------------
      Active:
        if (gen_ready) begin
          pos           <= pos + 1;
          checksum      <= checksum + gen_data;
          gen_data      <= gen_data + incr;
          if (gen_eof) begin
            pos         <= 0;
            checksum_r  <= checksum + gen_data;
            frame_count <= frame_count + 1;
            incr        <= incr + 1;
            gap_count   <= 0;
            state       <= Gap;
          end
        end
      // ----------------------------------------
      Gap: begin
        gap_count <= gap_count + 1;
        if (gap_count >= cfg_gap_len) begin
          state    <= Idle;
        end
      end
    endcase

    if (rst) begin
      state       <= Idle;
      pos         <= 0;
      frame_count <= 0;
      incr        <= 1;
    end

  end

  assign  gen_valid  = state == Active;
//  assign  gen_eof    = (pos == cfg_frame_len-1);
  assign  gen_eof    = (pos == frame_len_m1);

  // ---------------------------------
  // Stream Buffer to register output
  // ---------------------------------
  stream_buf_v #(
    .DataBits(DataBits+1))
  obuf (
    .clk       (clk),
    .rst       (rst),
    .in_valid  (gen_valid),
    .in_ready  (gen_ready),
    .in_data   ({gen_eof, gen_data}),
    .out_valid (dout_valid),
    .out_ready (dout_ready),
    .out_data  ({dout_eof, dout_data}));

endmodule
