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
// Stream Simulation Sink
// -----------------------------------------------------------------------------
// Receives a data stream and dumps this to a file. It can optionaly compare
// the data stream to a reference file and report any mismatches. This block
// will randomly assert and deassert 'ready' according to its parameters. The
// probability of ready being high will ramp-up and ramp-down between
// 'MinThroughput' and 'MaxThroughput'. See the 'rate_ctrl' module for details.
//
// By using relatively prime ramp periods for a stream source and sink, a
// design-under-test can be exercised under a variety of flow control scenarios.
//
// Each stream transaction will be saved onto a single line in the data file.
// The data input vector will be broken into individual symbols, separated
// by a space in the data file. The bit-widths of the data symbols are specified
// using the SYMBOL_BITS parameter
//
// Example reference data file:
//
//  100 1  # Optional Comment
//  200 2  # This data will be output on the 2nd valid cycle
//  300 3  # This data will be output on the third valid cycle
//
// -----------------------------------------------------------------------------
module stream_sink (clk, rst, din_valid, din_ready, din_data, done, err);
`include "stream_common.vh"
  //
  parameter FilenameDump  = "undefined"; // filename for data dump
  parameter FilenameRef   = "undefined"; // filename of reference data
  parameter CheckData     = 1;           // if true, compare data to reference
  parameter NumSymbols    = 2;           // number of symbols in the data vector
  parameter SymbolBits    = {32'd8, 32'd2};// bit-width of each symbol
                                           //  (32'bit slice for each)
  parameter MinThroughput = 0;    // Min probability 'valid' will be high
  parameter MaxThroughput = 100;  // Max probability 'valid' will be high
  parameter Period        = 1487; // Period for the throughput ramp function
  parameter Seed          = 2;    // seed for random number generation
  //
  localparam TotalWidth   = calc_total(NumSymbols, SymbolBits);
  //
  input                   clk;
  input                   rst;
  output                  din_ready;
  input                   din_valid;
  input  [TotalWidth-1:0] din_data;
  output                  done;
  output                  err;
  // --------------------------------------------------------------------------------

  // ------------------------------
  // Dump and Check Incoming Stream
  // ------------------------------
  stream_spy
    #(.FilenameDump(FilenameDump),
      .FilenameRef (FilenameRef),
      .NumSymbols  (NumSymbols),
      .CheckData   (CheckData),
      .SymbolBits  (SymbolBits))
  spy(
    .clk      (clk),
    .rst      (rst),
    .din_ready(din_ready),
    .din_valid(din_valid),
    .din_data (din_data),
    .done     (done),
    .err      (err));

  // --------------------
  // Control 'ready' Rate
  // --------------------
  rate_ctrl
    #(.MaxThroughput(MaxThroughput),
      .MinThroughput(MinThroughput),
      .Period       (Period),
      .Seed         (Seed))
  rate(
    .clk    (clk),
    .rst    (rst),
    .active (din_ready),
    .ack    (din_valid));

endmodule


