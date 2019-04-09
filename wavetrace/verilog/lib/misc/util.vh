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
// Utility Functions
// -----------------------------------------------------------------------------
//
// -----------------------------------------------------------------------------
function automatic [31:0] clog2(input integer x);
  integer       tmp, res;
  begin
    tmp = 1;
    res = 0;
    while(tmp < x) begin
      tmp = tmp * 2;
      res = res + 1;
    end
    clog2 = res;
  end
endfunction

function automatic integer min(input integer a,
                               input integer b);
  begin
    min = (a < b) ? a : b;
  end
endfunction

function automatic integer max(input integer a,
                               input integer b);
  begin
    max = (a > b) ? a : b;
  end
endfunction

function automatic integer onehot2bin (input integer one_hot, input integer bits);
  integer i;
  begin
    onehot2bin = 0;
    for (i = 0; i < bits; i=i+1) begin
      if (one_hot[i]) begin
        // 'OR' together conversions for each bit to reduce gate count
        onehot2bin = onehot2bin | i;
      end
    end
  end
endfunction
