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
// Wave Capture
// -----------------------------------------------------------------------------
// This module implements the trigger logic and capture memory necessary to
// store arbitrary debug signal data in an APB accessible memory. A set of APB
// registers configures the trigger conditions and sets the mode of operation.
//
// Two sets of trigger mask and comparisons are performed to support rising /
// falling edge detection. A fifo is used to store a certain amount of
// pre-trigger data. The 'go' register initiates the capture sequence, and
// should be cleared between captures.
//
// The capture sequence is as follows:
//  1. wait for trigger conditions to be met
//  2. transfer pre-trigger data to the capture memory
//  3. capture data until the capture memory is full
//  4. increment capture count register, which can be monitored via the APB bus
//
// There are three trigger modes supported:
//  0: None
//    no triggering is performed, data is captured as soon as the 'go'
//    register has been written to.
//  1: Single
//    the capture process waits until the trigger conditions have been
//    met and then proceeds to capture data until the buffer is full
//  2: Continuous
//    every time the trigger conditions are met, the capture sequence
//    is restarted and then proceeds until the bufer is full. This
//    means the capture buffer will always hold the data after the most
//    recent trigger. The trigger and capture count reigsters can be
//    monitored to determine when the contents of the capture have changed.
//
// -----------------------------------------------------------------------------
module wave_capture #(
  parameter  DataBits      = 32,
  parameter  PreTrigDepth  = 64,
  parameter  CaptDepth     = 512,
  parameter  ClockHz       = 80000000)
(
  input                    clk,
  input                    rst,
  //
  input [DataBits-1:0]     din_data,
  //
  input [31:0]             cfg_paddr,
  input                    cfg_pwrite,
  input [31:0]             cfg_pwdata,
  input                    cfg_psel,
  input                    cfg_penable,
  output reg               cfg_pready,
  output reg [31:0]        cfg_prdata,
  output                   cfg_pslverr
);

`include "util.vh"

  localparam CaptAddrBits  = clog2(CaptDepth);
  // we split the capture memory into 32-bit 'banks' to be compatible with a 32-bit APB interface
  localparam NumBanks = (DataBits + 31) / 32;
  localparam BankAddrBits = clog2(NumBanks);
  localparam TrigRegs = NumBanks;

  // -----------
  // Address Map
  // -----------
  localparam
    WhoAmIAddr       = 0,               // RO: readable register containing 0xABCD1234
    CaptDepthAddr    = 1,               // RO: CaptDepth parameter
    PreTrigDepthAddr = 2,               // RO: PreTrigDepth paramater
    DataBitsAddr     = 3,               // RO: DataBits paramater
    ClockHzAddr      = 4,               // RO: ClockHz parameter
    TrigModeAddr     = 5,               // RW: trigger mode: 0=none, 1=single, 2=continuous
    TrigCountAddr    = 6,               // RW: number of times trigger has been hit, write 0 to clear
    CaptCountAddr    = 7,               // RW: number of times capture has completed, write 0 to clear
    SubSampleAddr    = 8,               // RW: sub-samples the captured data by this ratio before storing
    GoAddr           = 9,               // RW: enables capture sequence
    CaptStateAddr    = 10,              // RO: reads capture state
    // ---- reserved -----
    TrigMask1Addr    = 16,              // RW: mask indicating which bits to use for first trigger stage
    TrigMask2Addr    = 16 + 1*TrigRegs, // RW: mask indicating which bits to use for sedond trigger stage
    TrigVal1Addr     = 16 + 2*TrigRegs, // RW: trigger value, first stage
    TrigVal2Addr     = 16 + 3*TrigRegs, // RW: trigger value, second stage
    // ---- reserved ----
    StoreMaskAddr    = 16 + 4*TrigRegs, // RW: mask indicating which bits to use for storage qualifier
    StoreValAddr     = 16 + 5*TrigRegs, // RW: value the masked data must match to qualify for storage
    CaptMemoryAddr   = CaptDepth << BankAddrBits; // RO: start of capture memory

  // Trigger types
  localparam None       = 0,
             Single     = 1,
             Continuous = 2;

  // Capture states
  localparam Idle      = 0,
             PreFill   = 1,
             ShiftOut  = 2,
             Capture   = 3,
             Done      = 4,
             NumStates = 5;

  reg [clog2(NumStates)-1:0] state, state_n;

  // -------------
  // APB Interface
  // -------------
  assign cfg_pslverr = 0; // unused

  reg [1:0]               trig_mode;
  reg [31:0]              trig_count, capt_count;
  reg                     capt_done, go;
  reg                     mem_rd;
  wire [31:0]             mem_data_mux;
  reg [4*TrigRegs*32-1:0] trig_setup_regs;    // {value2, value1, mask2, mask1}
  reg [2*TrigRegs*32-1:0] store_setup_regs; // {value, mask}
  reg [31:0]              sample_ratio;
  wire                    trig_hit, trig_hit_d;

  always @(posedge clk) begin :cfg
    integer addr_i;
    addr_i = cfg_paddr >> 2; // convert to word address

    // defaults
    mem_rd     <= 0;
    cfg_pready <= 0;

    // increase counters, allowing register writes to override this below
    if (capt_done) begin
      capt_count <= capt_count + 1;
    end
    if (trig_hit_d & go) begin
      trig_count <= trig_count + 1;
    end

    if (cfg_psel && !cfg_penable) begin
      // register writing
      if (cfg_pwrite) begin
        cfg_pready <= 1;
        if (addr_i < 16) begin
          case (addr_i)
            TrigModeAddr:  trig_mode    <= cfg_pwdata;
            TrigCountAddr: trig_count   <= cfg_pwdata;
            CaptCountAddr: capt_count   <= cfg_pwdata;
            SubSampleAddr: sample_ratio <= cfg_pwdata;
            GoAddr:        go           <= cfg_pwdata;
          endcase
        end else if (addr_i < 16 + 4*TrigRegs) begin
          trig_setup_regs[32*(addr_i - 16) +: 32] <= cfg_pwdata;
        end else if (addr_i < 16 + 6*TrigRegs) begin
          store_setup_regs[32*(addr_i - 16 - 4*TrigRegs) +: 32] <= cfg_pwdata;
        end
      // register reading
      end else begin
        if (addr_i < CaptMemoryAddr) begin
          cfg_pready <= 1;
          if (addr_i < 16) begin
            case (addr_i)
              WhoAmIAddr:       cfg_prdata <= 32'hABCD1234;
              CaptDepthAddr:    cfg_prdata <= CaptDepth;
              PreTrigDepthAddr: cfg_prdata <= PreTrigDepth;
              DataBitsAddr:     cfg_prdata <= DataBits;
              ClockHzAddr:      cfg_prdata <= ClockHz;
              TrigModeAddr:     cfg_prdata <= trig_mode;
              GoAddr:           cfg_prdata <= go;
              SubSampleAddr:    cfg_prdata <= sample_ratio;
              TrigCountAddr:    cfg_prdata <= trig_count;
              CaptCountAddr:    cfg_prdata <= capt_count;
              CaptStateAddr:    cfg_prdata <= state;
              default:          cfg_prdata <= 32'hDEADDEAD;
            endcase
          end else if (addr_i < 16 + 4*TrigRegs) begin
            cfg_prdata <= trig_setup_regs[32*(addr_i - 16) +: 32];
          end else if (addr_i < 16 + 6*TrigRegs) begin
            cfg_prdata <= store_setup_regs[32*(addr_i - 16 - 4*TrigRegs) +: 32];
          end else begin
            cfg_prdata <= 32'hDEADDEAD;
          end
        end else begin
          // read from capture memory
          mem_rd <= 1;
        end
      end
    end

    // delay memory reads by 1 cycle to account for latency through RAM
    if (mem_rd) begin
      cfg_prdata <= mem_data_mux;
      cfg_pready <= 1;
    end

    if (rst) begin
      trig_mode        <= None;
      trig_setup_regs  <= 0;
      store_setup_regs <= 0;
      trig_count       <= 0;
      capt_count       <= 0;
      go               <= 0;
      sample_ratio     <= 1;
    end
  end

  // split up trigger and storage setup regs into their relevant signals
  wire [DataBits-1:0] trig_mask1, trig_mask2, trig_val1, trig_val2, store_mask, store_val;
  assign trig_mask1 = trig_setup_regs[            0 +: DataBits];
  assign trig_mask2 = trig_setup_regs[  TrigRegs*32 +: DataBits];
  assign trig_val1  = trig_setup_regs[2*TrigRegs*32 +: DataBits];
  assign trig_val2  = trig_setup_regs[3*TrigRegs*32 +: DataBits];
  assign store_mask = store_setup_regs[          0 +: DataBits];
  assign store_val  = store_setup_regs[TrigRegs*32 +: DataBits];

  // -----------------
  // Trigger Detection
  // -----------------
  // use two sets of masked comparisons, delayed by 1 cycle, so that we
  // can detect rising and falling edges.

  // TODO: may want to disable subsequent triggers after the first one fires in 'single' mode
  //       otherwise if they continue to fire, we end up forcing these values to be stored even
  //       when sub-sampling or storage qualifiers are enabled.
  wire                trig1_result, trig2_result, trig_valid;
  wire [DataBits-1:0] trig_data;
  reg [DataBits-1:0]  din_data_d, din_data_dd;

  // register incoming data once in this clock domain, then delay
  // by one cycle for use in trigger detection
  always @(posedge clk) begin
    din_data_d  <= din_data;
    din_data_dd <= din_data_d;
  end

  mask_compare #(
    .DataBits (DataBits))
  trig_comp1(
    .rst       (rst),
    .clk       (clk),
    .din_valid (1'b1),
    .din_data  (din_data_dd),
    .din_sync  (1'b0),
    .mask      (trig_mask1),
    .value     (trig_val1),
    .dout_valid( ),
    .dout_data ( ),
    .dout_sync ( ),
    .result    (trig1_result));

  mask_compare #(
    .DataBits (DataBits))
  trig_comp2(
    .rst       (rst),
    .clk       (clk),
    .din_valid (1'b1),
    .din_data  (din_data_d),
    .din_sync  (1'b0),
    .mask      (trig_mask2),
    .value     (trig_val2),
    .dout_valid(trig_valid),
    .dout_data (trig_data),
    .dout_sync ( ),
    .result    (trig2_result));

  // trigger is hit when both comparisons match
  assign trig_hit = trig_valid & trig1_result & trig2_result & (trig_mode != None);

  // -----------------
  // Storage Qualifier
  // -----------------
  wire                store_valid, store_result;
  wire [DataBits-1:0] store_data;

  mask_compare #(
    .DataBits (DataBits))
  store_comp(
    .rst       (rst),
    .clk       (clk),
    .din_valid (trig_valid),
    .din_data  (trig_data),
    .din_sync  (trig_hit),
    .mask      (store_mask),
    .value     (store_val),
    .dout_valid(store_valid),
    .dout_data (store_data),
    .dout_sync (trig_hit_d),
    .result    (store_result));

  // Pass along data that either matches our storage qualifier or our trigger conditions
  // NOTE: this means triggered data is always captured, even when it doesn't meet
  //       the storage qualifier. The thinking here is that in these conditions, seeing
  //       the triggered data would be more user friendly. TBD if this is what we want...
  // TODO: if we capture triggered data when subsampling, then we should also capture
  //       the cycle before the trigger was hit so we see transitions.
  // TODO: Consider making this an option - sometimes trigger events are isolated, sometimes
  //       they occur back-to-back, and we don't want that to mean nothing gets subsampled
  wire qual_valid = store_valid & (trig_hit_d || store_result);

  // -----------
  // Sub-Sampler
  // -----------
  // Sub samples the data stream by some ratio before storing. This allows the
  // user to trade off capture-depth for resolution. The post-trigger sampling
  // is synchronized to the trigger condition.
  reg [31:0] sample_count;
  always @(posedge clk) begin
    if (qual_valid) begin
      if (sample_ratio > 1) begin
        if (trig_hit_d)
          sample_count <= 1;
        else if (sample_count == sample_ratio - 1)
          sample_count <= 0;
        else
          sample_count <= sample_count + 1;
      end else begin
        sample_count <= 0;
      end
    end
    if (rst) begin
      sample_count <= 0;
    end
  end

  wire sample_valid = (sample_count == 0 || trig_hit_d) ? qual_valid : 0;

  // ----------------------------
  // Fifo for pre-trigger storage
  // ----------------------------
  // We actually store PreTrigDepth + 1 elements so that we have an extra
  // cycle to react to the trigger before writing data to the capture memory.
  // The fifo is sized for PreTrigDepth + 2, this allows us to still operate
  // in a one-in-one-out mode when it contains PreTrigDepth + 1 elements.
  localparam UsedBits  = clog2(PreTrigDepth+2);

  wire                fifo_valid;
  wire [DataBits-1:0] fifo_data;
  wire [UsedBits-1:0] fifo_used;
  reg                 fifo_ready;

  stream_fifo_1clk #(
    .Width    (DataBits),
    .Depth    (PreTrigDepth+2))
  fifo(
    .rst       (rst),
    .clk       (clk),
    //
    .din_valid (sample_valid),
    .din_ready ( ),
    .din_data  (store_data),
    //
    .dout_valid(fifo_valid),
    .dout_ready(fifo_ready),
    .dout_data (fifo_data),
    .used      (fifo_used));

  // ----------------------
  // Capture State Machine
  // ----------------------
  reg [CaptAddrBits-1:0]     wr_addr, wr_addr_n;
  reg                        wr_en;

  always @(*) begin

    state_n     = state;
    wr_addr_n   = wr_addr;
    wr_en       = 0;
    capt_done   = 0;
    fifo_ready  = 1;

    case (state)
      // -------------------------------------
      Idle:
        begin
          if (go) begin
            state_n = PreFill;
          end
        end
      // -------------------------------------
      PreFill:
        begin
          fifo_ready = 0;
          if (trig_hit_d || trig_mode == None) begin
            state_n   = Capture;
            wr_addr_n = 0;
          end else if (fifo_used >= PreTrigDepth+1) begin
            state_n = ShiftOut;
          end
          if (!go) state_n = Idle;
        end
      // -------------------------------------
      ShiftOut:
        begin
          fifo_ready = sample_valid;
          if (trig_hit_d) begin
            state_n   = Capture;
            wr_addr_n = 0;
          end
          if (!go) state_n = Idle;
        end
      // -------------------------------------
      Capture:
        begin
          wr_en       = fifo_valid;
          wr_addr_n   = wr_addr + wr_en;
          if (trig_mode == Continuous && trig_hit_d) begin
            // if we hit another trigger in continous mode, restart the capture
            wr_addr_n = 0;
          end else if (wr_addr == CaptDepth-1 && wr_en) begin
            capt_done = 1;
            state_n   = (trig_mode == Continuous) ? PreFill : Done;
          end
          if (!go) state_n  = Idle;
        end
      // -------------------------------------
      Done:
        begin
          if (!go) state_n = Idle;
        end
    endcase
  end

  always @(posedge clk) begin
    state   <= state_n;
    wr_addr <= wr_addr_n;
    if (rst) begin
      state <= Idle;
    end
  end

  // ---------------
  // Capture Buffer
  // ---------------
  wire [DataBits-1:0]     mem_data;
  wire [CaptAddrBits-1:0] rd_addr = cfg_paddr[2 +: CaptAddrBits]; // convert to word address

  ram_1c_1r_1w #(
    .Width (DataBits),
    .Depth (CaptDepth))
  mem(
    .clk     (clk),
    .wr_en   (wr_en),
    .wr_addr (wr_addr),
    .wr_data (fifo_data),
    .rd_addr (rd_addr),
    .rd_data (mem_data));

  generate
    if (NumBanks > 1) begin :multi_banks
      // pad out the data to be a mulitple of 32 bits, then select the bank
      wire [NumBanks*32-1:0]  mem_data_padded = mem_data;
      wire [BankAddrBits-1:0] bank_addr = cfg_paddr[CaptAddrBits+2 +: BankAddrBits];
      assign mem_data_mux = mem_data_padded[bank_addr*32 +: 32];
    end else begin :one_bank
      assign mem_data_mux = mem_data;
    end
  endgenerate

endmodule
