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
// -----------------------------------------------------------------------------------------
// APB Master Simulation Module
// -----------------------------------------------------------------------------------------
// Reads APB instructions from a text file and executes the instructions on the APB bus.
//
// The following commands are supported
//  WR <address> <data>          : writes data to an address
//  RD <address> <expected_data> : reads data from an address and checks the data
//  RP <address> <poll_value>    : keeps reading the same address until the data matches
//  WT <irq_num>                 : waits for the irq line to be high
//  ST <cycles>                  : stalls for some number of cycles
//  # comment                    : comments can be on their own line or after a command
//
// Example input file:
//   WR 00000004 DEADBEEF  # writes 0xDEADBEEF to address 0x4
//   RD 00000004 DEADBEEF  # reads address 0x4 and compares data to 0xDEADBEEF
//   WT 0                  # waits for the irq[0] input to be high
//   WR 00000008 00000000  # writes 0 to address 0x8
//   RP 0000000C 00000001  # keeps reading address 0xC until it equals 0x1
//   ST 100                # do nothing for 100 cycles
//   WR 00000010 00000ABC  # writes 0xABC to address 0x10
//
// NOTE: All numbers are *hexadecimal*, and all addresses are *byte addresses*
//
//
// -----------------------------------------------------------------------------------------
module apb_master_sim #(
  parameter Filename = "undefined",
  parameter Verbose  = 1)
(
  input             clk,
  input             rst,
  output reg [31:0] mst_paddr,
  output reg        mst_pwrite,
  output reg [31:0] mst_pwdata,
  output reg        mst_psel,
  output reg        mst_penable,
  input             mst_pready,
  input [31:0]      mst_prdata,
  input             mst_pslverr, // **IGNORED**
  input [31:0]      irq,
  output reg        done,
  output reg        err
);

  // ------------
  // Helper Tasks
  // ------------
  // Task to perform a register write
  task do_write(input [31:0] addr, input [31:0] data); begin
    @(posedge clk);
    mst_paddr   <= addr;
    mst_pwdata  <= data;
    mst_pwrite  <= 1;
    mst_psel    <= 1;
    @(posedge clk);
    mst_penable <= 1;
    wait (mst_pready);
    @(posedge clk);
    mst_psel    <= 0;
    mst_penable <= 0;
    if (Verbose) begin
      $display("@%0t %0s: wrote 0x%08x to address 0x%08x",
                   $time, Filename, data, addr);
    end
  end endtask

  // Task to perform a register read
  task do_read(input [31:0] addr); begin
    @(posedge clk);
    mst_paddr  <= addr;
    mst_pwrite <= 0;
    mst_psel   <= 1;
    @(posedge clk);
    mst_penable <= 1;
    wait (mst_pready);
    @(posedge clk);
    mst_psel       <= 0;
    mst_penable    <= 0;
  end endtask

  // Task to perform a register read and compare it to an expected value
  task do_read_check(input [31:0] addr, input [31:0] expected); begin
    do_read(addr);
    if (mst_prdata !== expected) begin
      $display("@%0t %0s: Error, read 0x%x from address 0x%x, expected 0x%x",
               $time, Filename, mst_prdata, addr, expected);
      err <= 1;
    end else if (Verbose) begin
      $display("@%0t %0s: read 0x%08x from address 0x%08x",
               $time, Filename, mst_prdata, addr);
    end
  end endtask

  // Task to continue reading a register until it equals some value
  task do_read_poll(input [31:0] addr, input [31:0] value); begin
    if (Verbose) begin
      $display("@%0t %0s: polling address 0x%08x until it equals 0x%08x",
               $time, Filename, addr, value);
    end
    do_read(addr);
    while (mst_prdata !== value) begin
      do_read(addr);
    end
    if (Verbose) begin
      $display("@%0t %0s: read 0x%08x from address 0x%08x, done polling",
               $time, Filename, mst_prdata, addr);
    end
  end endtask

  // Task to stall for some number of cycles
  task do_stall(input integer cycles);
    integer i;
    begin
      if (Verbose) begin
        $display("@%0t %0s: stalling for %0d cycles", $time, Filename, cycles);
      end
      i  = 0;
      while (i < cycles) begin
        @(posedge clk);
        i = i + 1;
      end
    end
  endtask

  // Task to wait until a particular interrupt is high
  task do_wait(input integer irq_num); begin
    if (Verbose) begin
      $display("@%0t %0s: waiting for interrupt[%0d]", $time, Filename, irq_num);
    end
    @(posedge clk);
    while (!irq[irq_num]) begin
      @(posedge clk);
    end
    if (Verbose) begin
      $display("@%0t %0s: received interrupt[%0d]", $time, Filename, irq_num);
    end
  end endtask

  task fail(); begin
    $display("***SIMULATION FAILED***");
    $finish;
  end endtask

  task format_error(input integer line_num); begin
    $display("%0s: invalid format on line %0d", Filename, line_num);
    fail();
  end endtask

  // --------------------------
  // File reader and APB Master
  // --------------------------
  localparam [2*8-1:0] ReadInstr   = "RD",
                       PollInstr   = "RP",
                       WriteInstr  = "WR",
                       WaitInstr   = "WT",
                       StallInstr  = "ST";

  integer         fp, r;
  integer         stall_cycles, irq_num, line_count;
  reg [31:0]      addr, data, expected;
  reg [256*8-1:0] junk;
  reg [2*8-1:0]   instr;

  initial begin

    // Open file
    fp = $fopen(Filename, "r");
    if (!fp) begin
      $display("Error: unable to open file \"%0s\"", Filename);
      fail();
    end

    // Reset
    err          = 0;
    done         = 0;
    line_count   = 0;
    mst_psel     = 0;
    mst_pwrite   = 0;
    mst_penable  = 0;
    @(negedge rst);

    // Read file line by line
    while (!done) begin
      r = $fscanf(fp, "%0s", instr);
      /*
      if (r != 1) begin
        $display("Error reading file %0s at line %0d", Filename, line_count);
        fail();
      end
       */
      line_count = line_count + 1;

      // skip comments, blank lines, and eof
      if (r >= 1 && instr[7:0] != "#") begin

        case (instr)
          ReadInstr:
            begin
              r  = $fscanf(fp, "%x %x", addr, expected);
              if (r != 2) format_error(line_count);
              do_read_check(addr, expected);
            end

          PollInstr:
            begin
              r  = $fscanf(fp, "%x %x", addr, expected);
              if (r != 2) format_error(line_count);
              do_read_poll(addr, expected);
            end

          WriteInstr:
            begin
              r  = $fscanf(fp, "%x %x", addr, data);
              if (r != 2) format_error(line_count);
              do_write(addr, data);
            end

          WaitInstr:
            begin
              r  = $fscanf(fp, "%d", irq_num);
              if (r != 1) format_error(line_count);
              do_wait(irq_num);
            end

          StallInstr:
            begin
              r  = $fscanf(fp, "%d", stall_cycles);
              if (r != 1) format_error(line_count);
              do_stall(stall_cycles);
            end

          default:
            format_error(line_count);

        endcase
      end

      // throw away the rest of the line, including any comments
      r = $fgets(junk, fp);
      if ($feof(fp)) begin
        done = 1;
        $fclose(fp);
      end
    end

    $display ("%0s: reached end of file", Filename);

  end

endmodule
