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
// ---------------------------------------------------------------------------------
// Stream Simulation Spy
// ---------------------------------------------------------------------------------
// Observes a data stream and dumps it to a file. It can optionaly compare
// the data stream to a reference file and report any mismatches.
//
// Each stream transaction will be saved onto a single line in the data file.
// The data input vector will be broken into individual symbols, separated
// by a space in the data file. The bit-widths of the data symbols are specified
// using the SymbolBits parameter.
//
// Example reference data file:
//
//  100 1  # Optional Comment
//  200 2  # This data will be output on the 2nd valid cycle
//  300 3  # This data will be output on the third valid cycle
//
// -----------------------------------------------------------------------------
module stream_spy (clk, rst, din_ready, din_valid, din_data, done, err);
`include "stream_common.vh"
  parameter FilenameDump  = "undefined";   // filename for data dump
  parameter FilenameRef   = "undefined";   // filename of reference data
  parameter CheckData     = 1;             // if true, compare data to reference
  parameter NumSymbols    = 2;             // number of symbols in the data vector
  parameter SymbolBits    = {32'd8, 32'd2};// bit-width of each symbol
                                           //  (32'bit slice for each)
  localparam TotalWidth   = calc_total(NumSymbols, SymbolBits);
  //
  input                  clk;
  input                  rst;
  input                  din_ready;
  input                  din_valid;
  input [TotalWidth-1:0] din_data;
  output                 done;
  output                 err;
// -----------------------------------------------------------------------------

  // enable writer and checker on stream transactions
  wire enable  = din_valid & din_ready;

  // -----------------
  // Dump Data to File
  // -----------------
  file_writer
    #(.Filename   (FilenameDump),
      .NumSymbols (NumSymbols),
      .SymbolBits (SymbolBits))
  writer (
    .clk    (clk),
    .rst    (rst),
    .wr_en  (enable),
    .wr_data(din_data)
    );

  // ----------------------------
  // Check Against Reference File
  // ----------------------------
  wire [TotalWidth-1:0] rd_data;

  generate
    if (CheckData) begin
      file_reader
        #(.Filename   (FilenameRef),
          .NumSymbols (NumSymbols),
          .SymbolBits (SymbolBits))
      reader (
        .clk     (clk),
        .rst     (rst),
        .rd_en   (enable),
        .rd_valid(),
        .rd_data (rd_data),
        .done    (done)
      );

      integer line_num;
      reg     err_r;
      always @(posedge clk) begin
        if (rst) begin
          line_num <= 1;
          err_r    <= 0;
        end else if (enable) begin
          if (done) begin
            $display("Error: (\"%s\") received data past end of file",
                      FilenameRef);
          end else if (rd_data !== din_data) begin
            // TODO: check individual columns of data and print more
            //       useful error message
            $display("Error: (\"%s\", line %0d)", FilenameRef, line_num,
                     " received data does not match reference data",
                     " (received: 0x%x, expected: 0x%x)", din_data, rd_data);
            err_r <= 1;
          end
          line_num <= line_num + 1;
        end
      end
      assign err  = err_r;

    end else begin
      assign done = 1'b0;
      assign err  = 1'b0;
    end

  endgenerate

endmodule

