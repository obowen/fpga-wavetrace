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
// -------------------------------------------------------------------------
// Common functions for stream simulation modules
// -------------------------------------------------------------------------
//
// -------------------------------------------------------------------------

// Calculate the total width of a vector broken into columns where each
// column has a specified bit-width
function integer calc_total;
  input integer num_cols;
  input [2047:0] col_bits;
  integer        i;
  begin
    calc_total = 0;
    for (i=0; i < num_cols; i=i+1)
    begin
      calc_total  = calc_total + (col_bits >> (i*32)) & 32'hFFFFFFFF;
    end
  end
endfunction

// Gets the width of a particular symbol column from a vector giving
// the widths of each column
function integer get_symbol_width;
  input integer num_cols;
  input [2047:0] col_bits;
  input integer  index;
  begin
    get_symbol_width = (col_bits >> (index*32)) & 32'hFFFFFFFF;
  end
endfunction
