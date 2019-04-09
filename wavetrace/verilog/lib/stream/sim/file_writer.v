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
// File Writer
// -----------------------------------------------------------------------------
// Writes data symbols to a file. One line will be written for each cycle 'wr_en'
// is high. The data vector will be broken into symbols, which will be separated
// by spaces in the data file.
//
// -----------------------------------------------------------------------------
module file_writer (clk, rst, wr_en, wr_data);
`include "stream_common.vh"
  //
  parameter Filename     = "undefined";
  parameter NumSymbols  = 2;
  parameter SymbolBits  = {32'd8,32'd1};
  //
  localparam TotalWidth = calc_total(NumSymbols, SymbolBits);
  //
  input                   clk;
  input                   rst;
  input                   wr_en;
  input [TotalWidth-1:0] wr_data;
  // ---------------------------------------------------------------------------

  // ---------
  // Open File
  // ---------
  integer fp;
  initial begin
    fp  = $fopen(Filename, "w");
    if (!fp) begin
      $display("Error: unable to create file %s", Filename);
      $display("***SIMULATION FAILED***");
      $finish;
    end
  end

  // ----------------
  // Write Data Lines
  // ----------------
  integer               col_val, col_width, i;
  reg [TotalWidth-1:0] data_i;

  always @(posedge clk) begin
    if (wr_en) begin
      data_i       = wr_data;
      for (i=NumSymbols-1; i >= 0; i=i-1) begin
        col_width  = get_symbol_width(NumSymbols, SymbolBits, i);
        col_val    = data_i >> (TotalWidth - col_width);
        data_i     = data_i << col_width;
        $fwrite(fp, "%0d", col_val);
        if (i > 0)
          $fwrite(fp, " ");
      end
      $fwrite(fp, "\n");
    end
  end

endmodule
