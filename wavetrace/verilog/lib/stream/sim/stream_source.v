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
// Stream Simulation Source
// -----------------------------------------------------------------------------
// Reads one or more data elements from a file and outputs these as a stream.
// The block will randomly assert and deassert 'valid' according to its
// parameters. The probability of valid being high will ramp-up and ramp-down
// between 'MinThroughput' and 'MaxThroughput'. See the 'rate_ctrl' module for
// details.
//
// By using relatively prime ramp periods for a stream source and sink, a
// design-under-test can be exercised under a variety of flow control scenarios.
//
// The data file may contain one or more columns, separated by a space. These
// are concatenated together into a single output vector. The bit-widths of each
// column are specified using the parameter 'ColBits'.
//
// Example data file:
//
//  100 1  # Optional Comment
//  200 2  # This data will be output on the 2nd valid cycle
//  300 3  # This data will be output on the third valid cycle
//
// -----------------------------------------------------------------------------
module stream_source (clk, rst, dout_valid, dout_ready, dout_data);
`include "stream_common.vh"
  //
  parameter Filename    = "undefined";    // input data filename
  parameter NumSymbols  = 2;              // number of symbols in the data file
  parameter SymbolBits  = {32'd8, 32'd1}; // bit-widths of each symbol
                                          //  (32'bit slice for each)
  parameter MinThroughput = 0;    // Min probability 'valid' will be high
  parameter MaxThroughput = 100;  // Max probability 'valid' will be high
  parameter Period        = 1011; // Period for the throughput ramp function
  parameter Seed          = 1;    // seed for random number generation
  //
  localparam TotalWidth = calc_total(NumSymbols, SymbolBits);
  //
  input                    clk;
  input                    rst;
  input                    dout_ready;
  output                   dout_valid;
  output [TotalWidth-1:0]  dout_data;
  // ---------------------------------------------------------------------------

  // Enable reader and rate_ctrol on stream transactions
  wire enable = dout_valid & dout_ready;
  wire done;

  // -----------
  // File Reader
  // -----------
  wire [TotalWidth-1:0] rdr_data;
  wire                  rdr_valid;
  file_reader
    #(.Filename (Filename),
    .NumSymbols (NumSymbols),
    .SymbolBits (SymbolBits))
  rdr (
    .clk      (clk),
    .rst      (rst),
    .rd_en    (enable),
    .rd_valid (rdr_valid),
    .rd_data  (rdr_data),
    .done     (done)
    );

  // --------------------
  // Control 'valid' rate
  // --------------------
  wire active;
  rate_ctrl
    #(.MaxThroughput(MaxThroughput),
      .MinThroughput(MinThroughput),
      .Period       (Period),
      .Seed         (Seed))
  rate(
    .clk   (clk),
    .rst   (rst),
    .active(active),
    .ack   (enable));

  assign dout_valid  = active & rdr_valid;
  assign dout_data = (dout_valid) ? rdr_data : {TotalWidth{1'bx}};

endmodule
