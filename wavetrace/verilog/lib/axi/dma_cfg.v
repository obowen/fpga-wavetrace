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
// ----------------------------------------------------------------------------------------
// Dma Confg Register and APB Interface
// ----------------------------------------------------------------------------------------
// This module provides an APB interface and config registers for DMA transfers. It is
// shared by the 'dma_mem2strm' and 'dma_strm2mem' modules. Each DMA transaction contains
// a start address, a length, and a maximum burst size.
//
// The configuration registers are double buffered in this module. The valid register is
// used to control when config is transferred into the double buffer and to provide feedback
// on whether or not the block is currently holding a valid configuration.
//
// -----------------------------------------------------------------------------------------
module dma_cfg #(
  parameter AddrBits     = 32,
  parameter LengthBits   = 16,
  parameter BurstBits    = 5,
  parameter FifoUsedBits = 7)
(
  input                       clk,
  input                       rst,
  // APB Interface for Config
  input [5:0]                 cfg_paddr,     // byte address
  input                       cfg_psel,
  input                       cfg_penable,
  input                       cfg_pwrite,
  input [31:0]                cfg_pwdata,
  output                      cfg_pready,
  output reg [31:0]           cfg_prdata,
  output                      cfg_pslverr,
  output reg                  cfg_irq,
  //
  output  [AddrBits-1:0]      dma_start,     // memory start address for dma transfer
  output  [LengthBits-1:0]    dma_len,       // length of transfer in 64-bit words
  output  [BurstBits-1:0]     dma_burst,     // max burst size for transfer (AXI supports up to 16)
  output                      dma_valid,     // indicates cfg is valid and starts transfer
  input                       dma_done,      // pulses high on final word of transfer
  input [LengthBits-1:0]      dma_remain,    // number of words remaining in transfer
  input [FifoUsedBits-1:0]    dma_fifo_used, // number of words in the fifo
  input [9:0]                 dma_status,    // various stream status and debug signals
  input [1:0]                 dma_err,       // axi error code seen on response channel
  input [LengthBits-1:0]      dma_curr_len   // length used for current transfer (for debug)
);

  // -------------
  // Register Map
  // -------------
  localparam
    StartAddr     = 0, // RW: memory address for start of transfer (in bytes)
    LenAddr       = 1, // RW: length of transfer (in memory words)
    BurstAddr     = 2, // RW: size of AXI bursts (in memory words), max is 16
    ValidAddr     = 3, // Bit-0 (RW): indicates config is valid and processing should start,
                       //             cleared when config is moved into double buffer.
                       // Bit-1 (RW): indicates config is "sticky" and frames will be repeatedly
                       //             processed with current config registers.
                       // Bit-2 (RO): indicates double-buffer contains a valid configuration,
                       //             cleared when the dma transaction is done.
    StatusAddr    = 4, // RO: status of the various streams, see input port assignment
    RemainAddr    = 5, // RO: num bytes remaining in transfer
    FifoUsedAddr  = 6, // RO: num of words in the fifo
    IrqAddr       = 7, // RW: latched high at end of transfer, write a '0' to clear
    ErrAddr       = 8, // RW: holds last seen AXI error code, write zeros to clear
    PrevStartAddr = 9, // RO: start address of most recently completed dma transfer
    CurrLenAddr   = 10;// RO: length of current transfer

  // --------------
  // APB Interface
  // --------------
  assign cfg_pready  = 1;   // APB slave is always ready
  assign cfg_pslverr = 0;   // slave error is unused

  reg [AddrBits-1:0]          reg1_start, dma_start_prev;
  reg [LengthBits-1:0]        reg1_len;
  reg [BurstBits-1:0]         reg1_burst;
  reg                         reg1_valid, reg1_repeat;
  reg [1:0]                   last_err;
  wire                        reg1_ready;

  always @(posedge clk) begin :cfg
    integer   addr_i;
    addr_i = cfg_paddr >> 2; // convert to word address

    if (cfg_psel && !cfg_penable) begin
      // register writing
      if (cfg_pwrite) begin
        case (addr_i)
          StartAddr:  reg1_start                 <= cfg_pwdata[AddrBits-1:0];
          LenAddr:    reg1_len                   <= cfg_pwdata[LengthBits-1:0];
          BurstAddr:  reg1_burst                 <= cfg_pwdata[BurstBits-1:0];
          ValidAddr:  {reg1_repeat, reg1_valid}  <= cfg_pwdata;
          IrqAddr:    cfg_irq                    <= cfg_pwdata[0];
          ErrAddr:    last_err                   <= cfg_pwdata;
        endcase
      // register reading
      end else begin
        case (addr_i)
          StartAddr:     cfg_prdata <= reg1_start;
          LenAddr:       cfg_prdata <= reg1_len;
          BurstAddr:     cfg_prdata <= reg1_burst;
          ValidAddr:     cfg_prdata <= {dma_valid, reg1_repeat, reg1_valid};
          StatusAddr:    cfg_prdata <= dma_status;
          RemainAddr:    cfg_prdata <= dma_remain;
          FifoUsedAddr:  cfg_prdata <= dma_fifo_used;
          IrqAddr:       cfg_prdata <= cfg_irq;
          ErrAddr:       cfg_prdata <= last_err;
          PrevStartAddr: cfg_prdata <= dma_start_prev;
          CurrLenAddr:   cfg_prdata <= dma_curr_len;
        endcase
      end
    end

    // clear valid register when config is transferred into double buffer registers
    if (reg1_valid & reg1_ready)
      reg1_valid <= 0;

    // latch irq when dma transfer is done
    if (dma_done) begin
      cfg_irq         <= 1;
      dma_start_prev  <= dma_start;
    end

    // latch any non-zero error codes
    if (dma_err)
      last_err <= dma_err;

    if (rst) begin
      reg1_valid  <= 0;
      reg1_repeat <= 0;
      reg1_start  <= 0;
      reg1_len    <= 0;
      reg1_burst  <= 16;
      cfg_irq     <= 0;
      last_err    <= 0;
    end
  end

  // ------------------------------
  // Double buffer config registers
  // ------------------------------
  stream_buf_v #(
    .DataBits (AddrBits + LengthBits + BurstBits))
  cfg_buf(
    .clk      (clk),
    .rst      (rst),
    .in_valid (reg1_valid | reg1_repeat), // treat config as valid when the repeat bit is set
    .in_ready (reg1_ready),
    .in_data  ({reg1_start, reg1_len, reg1_burst}),
    .out_valid(dma_valid),
    .out_ready(dma_done),
    .out_data ({dma_start, dma_len, dma_burst}));

endmodule
