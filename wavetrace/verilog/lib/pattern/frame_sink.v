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
// Frame Sink
// -----------------------------------------------------------------------------
// Acts as a sink for a stream of data frames. An interrtupt is generated at the
// end of each frame and a checksum is exposed over the APB bus.
//
// -----------------------------------------------------------------------------
module frame_sink #(
  parameter DataBits = 8)
(
  input                 clk,
  input                 rst,
  //
  input [4:0]           cfg_paddr,
  input                 cfg_pwrite,
  input [31:0]          cfg_pwdata,
  input                 cfg_psel,
  input                 cfg_penable,
  output                cfg_pready,
  output reg [31:0]     cfg_prdata,
  output                cfg_pslverr,
  output reg            cfg_irq,
  //
  input                 din_valid,
  output                din_ready,
  input  [DataBits-1:0] din_data,
  input                 din_eof
);

  // -------------
  //  Address Map
  // -------------
  localparam StatusAddr     = 0, // RO: Stream Status for debug, bit[0]=din_valid, bit[1]=din_ready
             ChecksumAddr   = 1, // RO: checksum of last received frame
             PosCountAddr   = 2, // RO: position in the current frame
             FrameCountAddr = 3, // RO: number of frames received
             IrqAddr        = 4; // RW: irq register, latched high at end of frame, write '0' to clear

  // --------------
  // APB Interface
  // --------------
  assign cfg_pready  = 1;   // APB slave is always ready
  assign cfg_pslverr = 0;   // slave error is unused


  reg [31:0] frame_count;
  reg [31:0] checksum, checksum_r;
  reg [15:0] pos;


  always @(posedge clk) begin :cfg
    integer addr_i;
    addr_i = cfg_paddr >> 2; // convert to word address

    if (cfg_psel && !cfg_penable) begin
      // register writing
      if (cfg_pwrite) begin
        case (addr_i)
          IrqAddr:  cfg_irq <= cfg_pwdata[0];
        endcase

      // register reading
      end else begin
        case (addr_i)
          StatusAddr:     cfg_prdata <= {din_ready, din_valid};
          ChecksumAddr:   cfg_prdata <= checksum_r;
          PosCountAddr:   cfg_prdata <= pos;
          FrameCountAddr: cfg_prdata <= frame_count;
          IrqAddr:        cfg_prdata <= cfg_irq;
        endcase
      end
    end

    // latch irq
    if (din_valid & din_ready & din_eof)
      cfg_irq <= 1;

    if (rst) begin
      cfg_irq <= 0;
    end

  end

  // -----------
  // Frame Sink
  // -----------
  always @(posedge clk) begin

    if (din_valid && din_ready) begin
      if (din_eof) begin
        pos         <= 0;
        frame_count <= frame_count + 1;
        checksum_r  <= checksum + din_data;
        checksum    <= 0;
      end else begin
        pos      <= pos + 1;
        checksum <= checksum + din_data;
      end
    end

    if (rst) begin
      checksum    <= 0;
      pos         <= 0;
      frame_count <= 0;
    end
  end

  assign din_ready = 1;

endmodule
