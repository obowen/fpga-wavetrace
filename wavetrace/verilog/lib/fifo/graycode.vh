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
// Gray Code Conversion Functions
// -----------------------------------------------------------------------------
//
// -----------------------------------------------------------------------------

// Efficient conversion of reflected gray code into binary. This results in a
// combinatorial chain of XORs that is O(log(n)) where n is the number of bits
// in the gray code.
function automatic integer gray2bin(input integer gray, input integer bits);
  integer i, tmp;
  begin
    tmp = gray;
    for (i = clog2(bits-1); i >= 0; i=i-1) begin
      tmp  = tmp ^ (tmp >> 2**i);
    end
    gray2bin = tmp;
  end
endfunction

// Converts binary to reflected gray code using shift and XOR
function automatic integer bin2gray(input integer bin);
  begin
    bin2gray = (bin >> 1) ^ bin;
  end
endfunction
