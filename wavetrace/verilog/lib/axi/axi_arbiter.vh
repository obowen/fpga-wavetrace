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
// --------------------------------------------------------------------------------------
// Axi Arbiter Helper Functions
// --------------------------------------------------------------------------------------
//
// --------------------------------------------------------------------------------------

// Round robin scheduler based on Altera Cookbook arbiter example. Grants access to
// whichever master is next in line, using 'last_grant' vector as a starting point.
// Returns a one-hot signal indicating which master has been granted access.
// (www.altera.com/literature/manual/stx_cookbook.pdf)
function [Ports-1:0] round_robin(
    input [Ports-1:0]   request,    // request status masters
    input [Ports-1:0]   last_grant  // one-hot signal indicating previously granted master
  );
  reg   [2*Ports-1:0] double_req, double_grant;
  reg   [Ports-1:0]   base;
  begin
    if (request == 0) begin    // TODO: confirm that we need this
      round_robin = last_grant;
    end else begin
      base         = (last_grant << 1) | last_grant[Ports-1]; // rotate vector left by 1
      double_req   = {request, request};
      double_grant = double_req & ~(double_req - base);
      round_robin  = double_grant[Ports-1:0] | double_grant[2*Ports-1:Ports];
    end
  end
endfunction
