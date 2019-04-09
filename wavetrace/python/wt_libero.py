# Copyright 2019 Google LLC
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
""" Wavetrace Libero Helper Functions

This file provides a helper function to modify the Synthesis Project file to
include Wavetrace sources and modified HDL files with debug nets in place.

To use the modified project file, open Synplify Pro interactively, run this
script, and then reload the .prj file from within Synplify Pro (you should be
prompted to do this automatically). Next, re-run the synthesis and make sure
there are no errors. Next you'll want to make sure there are IO constraints
for the debug UART pins. Once this is done, go back to the Libero IDE and
run remaining design flow tools (compiler, place-and-route, and bit-file
generation). Once the board is programmed, you can interact with the Wavetrace
debugger using the WTHost class.

"""

# NOTES and TODOs
#
# IO Constraints:
# We need to find a better way of dealing with the debug uart IO pins. The
# problem is that the tool complains if the IO constraints are present before
# we've added the Wavetrace instance. On the other hand, if you forget to add
# them in after generating the wavetrace code, it doesn't give you an error that
# they are missing. One solution could be to require a dummy Wavetrace instance
# that is connected to the uart and that then gets replaced by the Wavetrace
# router tool. This could include some dummy APB registers so one can test out
# the UART before doing any debugging. We would probably require the user to
# provide the hierarchicical path where this dummy wt module is located.
#
# Filenames:
# This code is currently making a lot of assumptions about the file paths, like
# that they are on C: and that abosulte paths include "cygdrive/c". This needs
# to be improved.
#
import os
import re
import fileinput
import shutil
import ntpath

def modify_synplify_prj_file(debug_files, syn_prj_file, top_level):
  """Modifies a Synplify project file to include wavetrace debug files
  Args:
    debug_files: a list of debug source files to be added to the project
    syn_prj_file: path to the synthesis .prj file for this project
  """
  print "\nModifying synthesis project file '%s'" % syn_prj_file

  # make a list of all the wavetrace source files we need to add
  WT_SRC_DIR  = 'C:/misc/wavetrace/verilog/'
  OTH_SRC_DIR = 'C:/src/fpga/common/hdl/'

  wt_sources  = ['apb_master.v', 'uart.v', 'wavetrace.v', 'wave_capture.v', 'mask_compare.v']
  oth_sources = ['stream/stream_serializer.v', 'stream/stream_deserializer.v',
                 'fifo/stream_fifo_1clk.v',
                 'fifo/fifo_1clk.v', 'ram/ram_1r_1w.v']

  # read in the current project file
  with open(syn_prj_file) as infile:
    lines = infile.readlines()

  in_wt_region = False
  with open(syn_prj_file, 'w') as outfile:
    # add in wavetrace source files
    outfile.write('#---WT_DEBUG---\r\n')
    for src in wt_sources:
      outfile.write('add_file -verilog "%s"\r\n' % (WT_SRC_DIR + src))
    for src in oth_sources:
      outfile.write('add_file -verilog "%s"\r\n' % (OTH_SRC_DIR + src))
    # add in the debug files
    for f in debug_files:
      dbg_file = os.path.abspath(f)
      # TODO: find a better way...
      dbg_file = dbg_file.replace("/cygdrive/c/", "C:/")
      outfile.write('add_file -verilog "%s"\r\n' % (dbg_file))
    outfile.write('#---WT_DEBUG---\r\n')

    # write back the original lines, but discard any existing WT_DEBUG lines
    # which may be left over from the last time we ran this script.
    for line in lines:
      if "---WT_DEBUG---" in line:
        in_wt_region = not in_wt_region
      else:
        if not in_wt_region:
          #line = re.sub(r'top_module', r'top_module XXX', line)
          # HACK: change the top-level file, for some reason the existing one isn't working
          #       with libero, gives "Unkown HDL format" error
          # TODO: modify full path
          if top_level+".v" in line and line[0] != '#':
            line = '#' + line

#          if not "_wt0" in line:
#            line = line.replace("set_option -top_module %s" % (top_level),
#                                "set_option -top_module %s" % (top_level+"_wt0"))
          outfile.write(line)


#def modify_synplify_prj_file(file_substitutions, syn_prj_file):
#  """Modifies a Synplify project file to include wavetrace debug files
#  Args:
#    file_substitutions: a list of pairs of files substitutions. The first
#      element in each pair is the original filename, the second is the modified
#      filename containing the debug code. This should be generated by the
#      WTRouter.get_change_list() function
#
#    syn_prj_file: path to the synthesis .prj file for this project
#  """
#  print "\nModifying synthesis project file '%s'" % syn_prj_file
#
#  # build up a list of file substitutions
#  changes_mod = []
#  for c in file_substitutions:
#    orig_file = os.path.abspath(c[0])
#    new_file = os.path.abspath(c[1])
#
#    # TODO: find a better way...
#    orig_file = orig_file.replace("/cygdrive/c/", "C:/")
#    new_file  = new_file.replace("/cygdrive/c/", "C:/")
#
#    changes_mod.append([orig_file, new_file])
#
#  # make a list of all the wavetrace source files we need to add
#  WT_SRC_DIR  = 'C:/misc/wavetrace/verilog/'
#  OTH_SRC_DIR = 'C:/src/raygun/hdl/'
#
#  wt_sources  = ['apb_master.v', 'uart.v', 'wavetrace.v', 'wave_capture.v']
#  oth_sources = ['stream/stream_serializer.v', 'stream/stream_deserializer.v',
#                 'fifo/work_in_progress/stream_fifo_1clk_INFERRED.v',
#                 'fifo/work_in_progress/fifo_1clk_INFERRED.v', 'ram/ram_1r_1w.v']
#
#  # read in the current project file
#  with open(syn_prj_file) as infile:
#    lines = infile.readlines()
#
#  in_wt_region = False
#  with open(syn_prj_file, 'w') as outfile:
#    # add in wavetrace source files
#    outfile.write('#---WT_DEBUG---\r\n')
#    for src in wt_sources:
#      outfile.write('add_file -verilog "%s"\r\n' % (WT_SRC_DIR + src))
#    for src in oth_sources:
#      outfile.write('add_file -verilog "%s"\r\n' % (OTH_SRC_DIR + src))
#    outfile.write('#---WT_DEBUG---\r\n')
#
#    # write back the original lines after applying our file substitutions.
#    # but discard any existing WT_DEBUG lines which may be left over from the
#    # last time we ran this script.
#    for line in lines:
#      if "---WT_DEBUG---" in line:
#        in_wt_region = not in_wt_region
#      else:
#        if not in_wt_region:
#          for c in changes_mod:
#            line = line.replace(c[0], c[1])
#          outfile.write(line)

