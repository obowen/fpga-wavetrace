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
// File Reader
// -----------------------------------------------------------------------------
// Reads data symbols from a file. Each line of the data file may contain one or
// more symbols, separated by a space. The symbols on each line are concatenated
// together into a single data vector.
//
// This block will preemptively read the first line from the data file.
// Subsequent lines will be read on clock cycles when 'enable' is high.
//
// The 'done' output will be asserted when the end-of-file is reached.
//
// -----------------------------------------------------------------------------
module file_reader (clk, rst, rd_en, rd_valid, rd_data, done);
`include "stream_common.vh"
  //
  parameter Filename   = "undefined";  // input data filename
  parameter NumSymbols = 2;             // number of symbols in the data file
  parameter SymbolBits = {32'd8,32'd1}; // bit-widths of each symbol
                                        //  (32'bit slice for each)
  //
  localparam TotalWidth = calc_total(NumSymbols, SymbolBits);
  //
  input                       clk;
  input                       rst;
  input                       rd_en;
  output                      rd_valid;
  output reg [TotalWidth-1:0] rd_data;
  output                      done; // goes high when at end-of-file
  // ---------------------------------------------------------------------------

  // ---------
  // Open File
  // ---------
  integer fp;
  initial begin
    fp  = $fopen(Filename, "r");
    if (!fp) begin
      $display("Error: unable to open file \"%s\"", Filename);
      $display("***SIMULATION FAILED***");
      $finish;
    end
  end

  // ---------------
  // Read Data Lines
  // ---------------
  integer              col_width;
  integer              col_val;
  reg                  started;
  reg                  eof;
  reg [TotalWidth-1:0] data_i;
  reg [256*8-1:0]      junk;
  integer              i, r;

  always @(posedge clk) begin
    if (rst) begin
      started  <= 1'b0;
      eof      <= 1'b0;
    end else begin
      if (!eof && (!started || rd_en)) begin
        started <= 1'b1;

        // read each symbol
        data_i   = 0;
        for (i=NumSymbols-1; i >= 0; i=i-1) begin
          r          = $fscanf(fp, "%d", col_val);
          col_width  = get_symbol_width(NumSymbols, SymbolBits, i);
          data_i     = (data_i << col_width) | col_val;
        end
        rd_data  <= data_i;

        // throw away the rest of the line, including any comments
        r = $fgets(junk, fp);
        if ($feof(fp)) begin
          eof <= 1'b1;
          $fclose(fp);
        end

      end
    end
  end

  assign done     = eof;
  assign rd_valid = started & ~done;

endmodule
