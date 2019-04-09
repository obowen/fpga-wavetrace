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
"""Wavetrace Setup Tool

Modifies a Verilog design to instantiate a Wavetrace module at the top-level
and route debug nets up through the hierarchy to the Wavetrace module.

  Typical usage example:

  import wt_setup
  wt = WTSetup(clk_freq=80.0)
  wt.sources("my_src_path/rtl")
  wt.top("top")
  wt.clk("clk")
  wt.net("module1.din_valid)
  wt.net("module1.din_data[7:0]")
  wt.generate()

"""
# TODO
# 1. Support this syntax to avoid digging into all subdirs:
#    'add_sources("../source/*.v")'
# 2. Create wavetrace_stub module with uart pins that can be instantiated
#    in the top-level and then replaced with the debug instance. This would
#    help ensure the UART pins get assigned and avoid needing to unassign them
#    when the debugger is removed.
# 3. Fix 'src_path' member variable which should keep a list of source paths
#    and various error messages need to be updated to to display that list,
#    or don't display the search path at all?
# 4. Support hierarchical clock and reset nets
# 5. Speed up data readout with burst reads, faster baud?
# 6. Re-think trigger position, should be run-time configurable, at least
#    in single trigger mode.
# 7. Add progress percentage when reading captured data.
# 8. Change sample count on waveform to reflect sub-sampling ratio
# 9. Subsampling and continous trigger isn't working right, not seeing trigger
#    condition in capture
# 10. Fix issues with widths > 32 bits, there is a limitation imposed in wt_capture
#     because of how memory bank vectors are concatenated
# 11. Sample count is no longer showing up on the waveform
# 12. Error message when max capture size is exceeded, this is related to number
#     of bits used for the APB addressing.
import shutil
import os
import sys
import re
import ntpath
from wt_parser import Vparse
from pyparsing import ParseException
import wt_util as util

OUTPUT_DIR = "output/"

# -------------------------------------------------------------------------------
class DbgNet(object):
  """Represents a single net which is to be debugged using Wavetrace

  Attributes:
    path: the hierarchical path of the net and range
    name: the signal name of the net including the range
    bit_width: the bit-width of the net
    has_range: if the net is defined with a bit-range [x:x], i.e. it is a vector
    vector_pos: position of this net within the top-level debug data vector
  """
  def __init__(self, path, has_range):
    self.path = path
    self.name = path.split('.')[-1];
    self.bit_width = util.net_width(self.name)
    self.has_range = has_range
    self.vector_pos = None

# ------------------------------------------------------------------------------
class DbgInstance(object):
  """Represents a verilog instance being debugged.

  Attributes:
    name: the name of the instance within the hierarchy
    module_type: the type of module for this instance
    local_nets: a list of all local nets being debugged
    sub_instances: a list of all debug instances instantiated within this module
    port_width: total bit width of the debug output port for this instance
    is_top: true if this is the top-level instance being debugged
    inst_id: id used to differentiate debug instances of the same module_type
  """
  def __init__(self, name, is_top=False):
    self.name = name
    self.module_type = None
    self.filename = None
    self.local_nets = []
    self.sub_instances = []
    self.port_width = None # bit-width of this modules top-level debug port
    self.is_top = is_top
    self.inst_id = 0

  def get_sub_instance(self, name):
    """ Gets a sub-instance by name"""
    for m in self.sub_instances:
      if m.name == name:
        return m
    return None

  def print_tree(self, offset):
    """ Recursively prints a tree of this instance and all sub-instances."""
    indent = " " * offset
    print self.name, "(%s)" % self.module_type
    if len(self.local_nets) > 0:
      for n in self.local_nets:
        print "%s|- %s" % (indent, n.name)

    for m in self.sub_instances:
      print "%s|-" % (indent),
      m.print_tree(offset+3)

  def set_port_widths(self):
    """Recursively sets the width of this instance's debug port and that of
    all sub-instances.
    """
    self.port_width = sum(net.bit_width for net in self.local_nets)
    for i in self.sub_instances:
      self.port_width += i.set_port_widths()
    return self.port_width

  def set_vector_pos(self, offset):
    """Recursively sets the position of this instance's nets within the overall
    debug vector, and does the same for all sub-instances.
    """
    pos = offset
    for n in self.local_nets:
      # set position of the MSB
      pos += n.bit_width
      n.vector_pos = pos - 1
      #print "%s: pos = %s" % (n.path, n.vector_pos)

    for i in self.sub_instances:
      pos = i.set_vector_pos(pos)
    return pos

  # TODO: decide on the best way to get the signal list, also, decide if we need
  #       to compute the vector positions, or if it is good enough to just write
  #       the signals in order into the "signal_list" file.
  def write_signals_in_order(self, fp):
    """Recursively writes out the names of all signals and widths in the order in which they get
    concatenated together in the debug vector.
    """
    for n in self.local_nets:
      # set position of the MSB
      fp.write(n.path+"\n")

    for i in self.sub_instances:
      i.write_signals_in_order(fp)

  def locate_items(self):
    """ Recursively locates the relevant debug items in this instance.
    These include: the module portlist, all sub-instances, and the location for
    assignments
    """
    # locate the module declaration to find the port list area
    try:
      res = Vparse.locate_module(self.filename, self.module_type)
      self.module_location = res['mod_loc']
      self.port_location = res['port_loc']
    except ParseException as excep:
      print excep
      util.error("failed to locate module '%s' in file '%s'" % (self.module_type, self.filename))

    # locate all sub-instances
    self.instance_locations = []
    for inst in self.sub_instances:
      try:
        res = Vparse.locate_instance(self.filename, self.module_type, inst.name)
        self.instance_locations.append(res)
      except ParseException as e:
        util.error("failed to locate instance '%s' in file '%s'" %
                   (inst.name, self.filename))

    # locate where we can place net declaration statements in the module
    try:
      self.declaration_location = Vparse.locate_declaration(
        self.filename, self.module_type)['declaration_loc']
    except ParseException as excep:
      util.error("failed to locate declaration area for module '%s' in file '%s'" % (
        self.module_type, self.filename))

    # locate the end of the module, which is where we'll put our assign statements
    try:
      self.endmodule_location = Vparse.locate_endmodule(
        self.filename, self.module_type)['endmodule_loc']
    except ParseException as excep:
      print excep
      util.error("failed to locate location of 'endmodule' in filename '%s'" % self.filename)

    # now do the same for all sub-instances
    for inst in self.sub_instances:
      inst.locate_items()

  def _write_debug_block(self, fp, line, col, content):
    """Helper function to add debug lines to a file."""
    add_cr = line[col] != '\n'
    fp.write(line[0:col])
    fp.write("\n//---WT_DEBUG---\n")
    fp.write(content)
    fp.write("//---WT_DEBUG---\n")
    fp.write(line[col:-1])
    if (add_cr): fp.write('\n')

  def _get_assign_string(self):
    """Gets a string containing a comma separated list of all local debug nets
    and instance nets
    """
    sigs = []
    for i in reversed(self.sub_instances):
      sigs.append(i.name+"_wt_debug")
    for n in reversed(self.local_nets):
      sigs.append(n.name)
    # join signals into a long string with line breaks and indentation
    str = (",\n" + " "*21).join(sigs)
    return str

  def generate_hdl(self, wt_instance_string, debug_files):
    """Recursively generates a modified debug verilog file for this instance and
    all sub-instances, containing the wavetrace debug ports and nets.
    """
    # TODO: this code became rather messy, find a cleaner way of doing this
    with open(self.filename) as infile:
      # get output filename
      basename = ntpath.basename(self.filename)
      (fname, ext) = ntpath.splitext(basename)
      # generate a unique module for each debug instance of the same module type
      id_str = "_wt%d" % self.inst_id
      filename_out = OUTPUT_DIR + fname + id_str + ext
      if not os.path.exists(OUTPUT_DIR):
        os.makedirs(OUTPUT_DIR)
      # TODO: detect unix/windows file and insert appropriate line endings
      #       NOTE: it seems that libero may have issues with mixed line endings in top level file?
      with open(filename_out, 'w') as outfile:
        #### HACK: to deal with declaration and port location being on the same
        #          line which is causing problems with verilog-95 style modules
        #          such as fifo_1clk.v
        if self.port_location[0] == self.declaration_location[0]:
          self.declaration_location[0] += 1
          self.declaration_location[1] = 0
        #####
        for curr_line_num, curr_line_str in enumerate(infile):
          # check if we're at the line number matching one of the sub-instances,
          # if so, modify the instance_type and/or insert the debug port
          inst_match = False
          for j, inst_loc in enumerate(self.instance_locations):
            col = inst_loc['port_loc'][1]
            found_inst_type = False
            if curr_line_num == inst_loc['inst_type_loc'][0] - 1:
              # substitute the original instance type with the debug instance type
              mod_type = self.sub_instances[j].module_type
              id_str = "_wt%d" % self.sub_instances[j].inst_id
              # replace only the first instance of the module name to
              # avoid replacing the instance name too
              curr_line_str = curr_line_str.replace(mod_type, mod_type + id_str, 1)
              col += len(id_str)
              found_inst_type = True

            # Note that we may find both the instance_type and instance ports
            # on the same line
            if curr_line_num == inst_loc['port_loc'][0] - 1:
              prefix = self.sub_instances[j].name
              content = "    .wt_debug(%s_wt_debug),\n" % (prefix)
              self._write_debug_block(outfile, curr_line_str, col, content)
              inst_match = True
              break
            elif found_inst_type:
              outfile.write(curr_line_str)
              inst_match = True
              break

          # otherwise, proceed with the rest of the checks
          if not inst_match:
            [port_line, port_col, mod_style] = self.port_location
            # check if we're at the location of the module declaration
            found_module_decl = False
            if curr_line_num == self.module_location[0] - 1:
              # modify the module name to differentiate it from the original module and
              # any other debug versions which may be defined
              if self.is_top:
                id_str = ""
              else:
                id_str = "_wt%d" % self.inst_id
              curr_line_str = curr_line_str.replace(self.module_type,
                                                    self.module_type + id_str)
              port_col += len(id_str)
              found_module_decl = True

            # check if we're at the line number of the module's port declaration,
            # this may be the same line as the module declaration
            if curr_line_num == port_line - 1:
              if mod_style == Vparse.MOD_STYLE_2001:
                if self.is_top:
                  content =  "  input  wt_uart_rx,\n"
                  content += "  output wt_uart_tx,\n"
                else:
                  content = "  output [%d:0] wt_debug,\n" % (self.port_width-1)
              else:
                if (self.is_top):
                  content =  "  wt_uart_rx,\n"
                  content += "  wt_uart_tx,\n"
                else:
                  content = "  wt_debug,\n"
              self._write_debug_block(outfile, curr_line_str, port_col, content)
              continue
            elif found_module_decl:
              outfile.write(curr_line_str)
              continue

            # TODO: We're skipping the declaration location if it is the same
            #       line number as the port location. FIX IT.
            # UPDATE: hacked this to work for now by increasing declaration
            # line number

            # check if we're at the location where we can declare our nets
            if curr_line_num == self.declaration_location[0] - 1:
              content = ""
              # we need to redeclare outputs if using verilog-95 style modules
              if mod_style == Vparse.MOD_STYLE_1995:
                if (self.is_top):
                  content +=  "  input  wt_uart_rx;\n"
                  content += "  output wt_uart_tx;\n"
                else:
                  content += "  output [%d:0] wt_debug;\n" % (self.port_width-1)
              # declare top-level debug vector
              if (self.is_top):
                content += "  wire [%d:0] wt_debug;\n" % (self.port_width-1)
              # declare local nets needed for sub-instances
              for j in self.sub_instances:
                content += "  wire [%d:0] %s_wt_debug;\n" % \
                           (j.port_width-1, j.name)
              col = self.declaration_location[1]
              if len(content) > 0:
                self._write_debug_block(outfile, curr_line_str, col, content)
              else:
                outfile.write(curr_line_str)

            # check if we're at the line number for the endmodule, which is
            # where we insert the assign statement and wavetrace instance
            elif curr_line_num == self.endmodule_location[0] - 1:
              # assign the debug vector for this level
              content = "  assign wt_debug = {%s};\n" % (self._get_assign_string())
              # if this is the top level, we also add the wavetrace instance
              if self.is_top: content += wt_instance_string

              # get the column location just before the 'endmodule' keyword
              col = self.endmodule_location[1] - 1
              self._write_debug_block(outfile, curr_line_str, col, content)

            # all other lines just get copied verbatim
            else:
              outfile.write(curr_line_str)

      debug_files.append(filename_out)
    # geneate hdlf files for all sub_instances
    for inst in self.sub_instances:
      inst.generate_hdl("", debug_files)

# -----------------------------------------------------------------------------
class WTSetup(object):
  """Provides an API for defining debug systems and generating debug verilog files.

  Attributes:
    clock_freq: clock frequency of the capture clock
    uart_baud: baud rate of the uart connecting to the debug module
    pre_trig_depth: depth of the pre-trigger capture memory
    capt_depth: depth of the post-trigger capture memory
    src_path: path to root directory of source code
    src_modules: list of all modules defined in the source code
    top_level: top-level module (instance of 'DbgInstance' class)
    clk_net: top-level net used as the capture clock
    rst_net: top-level net used to reset the wavetrace module
    net_paths: a list of hierarchical net paths for debug
    data_bits: total data width of all debug nets
    debug_files: list of old and new filename pairs after generating verilog
  """
  def __init__(self, clock_freq, uart_baud=115200, pre_trig_depth=64, capt_depth=512):
    self.clock_freq = clock_freq
    self.uart_baud = uart_baud
    self.pre_trig_depth = pre_trig_depth
    self.capt_depth = capt_depth
    self.src_path = None
    self.src_modules = []
    self.top_level = None
    self.clk_net = ""
    self.rst_net = ""
    self.net_paths = []
    self.data_bits = 0
    self.debug_files = []

  def add_sources(self, path):
    """Adds verilog sources and searches through them to find module definitions.
    Args:
      path: this can be a single Verilog file, or a directory. If it is a directory,
        all verilog files within it, and any subdirectories, are added too.
    """
    self.src_path = path  # TODO: this should contain a list of source paths, and
                          #       various error messages need to be updated
    vfiles = []
    print "Adding sources from directory '%s'..." % path
    path = os.path.expanduser(path)  # support '~' in path
    if os.path.isfile(path):
      vfiles.append(path)
    elif os.path.isdir(path):
      for (dirpath, dirnames, filenames) in os.walk(path):
        dirpath_clean = dirpath.rstrip('/')
        for f in filenames:
          if not f.startswith(".") and (f.endswith(".v") or f.endswith(".sv")):
            vfiles.append(dirpath_clean+"/"+f)
    else:
      util.error("Invalid path or directory '%s'" % path)

    # look for modules
    num_found = 0
    for fname in vfiles:
      try:
        res = Vparse.parse_modules(fname)
        for r in res:
          self.src_modules.append([r, fname])
          num_found += 1
      except ParseException as excep:
        print "Warning: unable to locate verilog module in file '%s'" % fname
    print "Found %d modules in %d verilog files" % (num_found, len(vfiles))
    print ""

  def rm_sources(self, path):
    # TODO: comment this and fix it up. It doesn't work reliably, for
    # example, it is not removing reed solomon sources for example. Also,
    # might be better to build up list of files and remove with these two
    # functions, then do the search for modules later
    vfiles = []
    if os.path.isfile(path):
      vfiles.append(path)
    elif os.path.isdir(path):
      for (dirpath, dirnames, filenames) in os.walk(path):
        for f in filenames:
          if not f.startswith(".") and (f.endswith(".v") or f.endswidth(".sv")):
            vfiles.append(dirpath+"/"+f)

    print vfiles
    for f in vfiles:
      for m in self.src_modules:
        if f == m[1]:
          self.src_modules.remove(m)

  def _module_exists(self, module_type):
    """Checks if a module exists in our list of source modules."""
    matches = []
    for m in self.src_modules:
      if (m[0] == module_type):
        matches.append(m[1])
    if len(matches) == 0:
      return False
    elif len(matches) > 1:
      util.error(
        "Found multiple definitions for module '%s' " % module_type +
        "in these files: " + ", ".join(matches) + ". "
        "You can exclude source files or directories with the 'rm_sources()' "
        "function)")
      return False
    return True

  def _get_fname(self, mod_name):
    """Gets the filename in which a particular module is defined."""
    for m in self.src_modules:
      if (m[0] == mod_name):
        return m[1]

  def top(self, module_type):
    """Sets the top-level module for the wavetrace debugger.
    Args:
      module_type: The type of the module eg. 'sys_top'. This module should only be
                   instantiated once in the design.
    """
    if not self.src_path:
      util.error("Please specify a root directory for your verilog sources using "
            "the 'wt.sources()' function.")
    if not self._module_exists(module_type):
      util.error("Cannot find top level module '%s' within search path '%s/'" %
            (module_type, self.src_path))
    self.top_level = DbgInstance("Top", is_top=True)
    self.top_level.module_type = module_type
    self.top_level.filename = self._get_fname(module_type)

  def clk(self, clk_net):
    """Selects the capture clock.
    Args:
      clk_net: the top-level net to be used as the capture clock.
    """
    if '.' in clk_net:
      util.error("Hierarchical clock nets are not supported yet. "
            "Please use a top-level clock net instead.")
    self.clk_net = clk_net

  def rst(self, rst_net):
    """Selects the reset net for the wavetrace module.
    Args:
      rst_net: the top-level net to be used as the reset
    """
    if '.' in rst_net:
      util.error("Hierarchical reset nets are not supported yet. "
            "Please use a top-level reset net instead.")
    self.rst_net = rst_net

  def net(self, *args):
    """Adds one or more debug nets.
    Args
      base: (Optional) A hierarchical base path to be prefixed to all nets
      nets: A single hierarchical path for a net, or a list of net paths.
            Multi-bit net paths must include the bit range,
            eg. "instance1.instance2.somenet[3:0]"
    """
    base = ""
    if len(args) == 1:
      nets = args[0]
    elif len(args) == 2:
      base = args[0] + "."
      nets = args[1]
    else:
      util.error("Invalid number of arguments passed to 'net' function")

    if type(nets) is not list:
      nets = [nets]

    for n in nets:
      # check that bit-width selection is only done across a single dimension
      # (we don't currently support multi dimensional arrays).
      if n.count('[') > 1:
        util.error("Bad net format '%s' (multi-dimensional arrays are not"
                   " supported)" % n)
      width = util.net_width(n)
      self.net_paths.append(base + n)

  def _build_data_structure(self):
    """Loops through all of the debug nets and builds up a hierarchical data structure
       of debug instances along with their local nets.
    """
    # dictionary counting number of debug instances associated with
    # a particular module_type, filename is used as the key
    instance_count = {}
    for path in self.net_paths:
      # for each level of hierarchy in this net, check if the instance exists, if not, add it
      curr_instance = self.top_level
      hierarchy = path.split('.');
      levels = len(hierarchy)
      for i in xrange(levels):
        curr_file = curr_instance.filename
        # if we're at the net level, add the net to the current module
        if i == levels - 1:
          net_string = hierarchy[i]
          net_name = net_string.split('[')[0]
          print "Adding debug net '%s'" % net_name

          # check if the net is a single-bit or multi-bit vector
          net_type = Vparse.check_net_type(curr_file, net_name)
          if (net_type == "none"):
            util.error("Unable to locate net '%s' in file '%s'" %
                       (net_name, curr_file))
          net = DbgNet(path, net_type == "vector")

          # if the net is a multi-bit vector, we require the user to specify a bit-range.
          if not '[' in path and net.has_range:
            util.error("Unable to extract bit range from net name '%s',\n"
                       "please append '[x:y]' or '[x]' to all multi-bit nets." % path)

          curr_instance.local_nets.append(net)
        else:
          sub_inst_name = hierarchy[i]
          sub_inst = curr_instance.get_sub_instance(sub_inst_name)
          if sub_inst is None:
            sub_inst = DbgInstance(sub_inst_name)
            # get the type of this module from the verilog code
            try:
              inst_res = Vparse.locate_instance(
                curr_file, curr_instance.module_type, sub_inst.name)
            except ParseException as excep:
              util.error("failed to locate instance '%s' in file '%s', "
                         "as specified by net '%s'" %
                         (sub_inst.name, curr_file, path))

            # make sure we have the source file for this type of instance
            inst_type = inst_res['inst_type']
            if not self._module_exists(inst_type):
              util.error("Cannot find module '%s' for instance '%s' needed for "
                         "net '%s'.\nCheck that the source code has been "
                         "added with 'add_sources()' function" %
                         (inst_type, sub_inst.name, path))
            # set the details of this sub instance
            sub_inst.module_type = inst_res['inst_type']
            fname = self._get_fname(sub_inst.module_type)
            sub_inst.filename = fname

            # keep track of how many debug instances of this module type we've created,
            # this is used to generate a unique id for each instance
            instance_count[fname] = instance_count.get(fname, 0) + 1
            sub_inst.inst_id = instance_count[fname] - 1

            curr_instance.sub_instances.append(sub_inst)

          curr_instance = sub_inst

    # recursively set the port widths and vector positions for each instance
    self.data_bits = self.top_level.set_port_widths()
    self.top_level.set_vector_pos(0)

  def _wt_instantiation(self):
    """Returns Verilog code to instantiate the wavetrace module."""
    r =  "  wavetrace #(\n"
    r += "    .DataBits    (%d),\n" % self.data_bits
    r += "    .PreTrigDepth(%d),\n" % self.pre_trig_depth
    r += "    .CaptDepth(%d),\n"    % self.capt_depth
    r += "    .ClockHz     (%d),\n" % int(self.clock_freq * 1e6)
    r += "    .UartBaud    (%d))\n" % self.uart_baud
    r += "  wavetrace(\n"
    r += "    .clk     (%s),\n" % self.clk_net
    r += "    .rst     (%s),\n" % self.rst_net
    r += "    .uart_rx (wt_uart_rx),\n"
    r += "    .uart_tx (wt_uart_tx),\n"
    r += "    .din_data(wt_debug));\n"
    return r

  def generate_signal_list(self):
    sig_filename = "output/signal_list.txt"
    with open(sig_filename, 'w') as fp:
      self.top_level.write_signals_in_order(fp)

  def generate(self):
    """Generates modified verilog source files with debug ports and nets."""

    # do some error checking
    if not self.top_level:
      util.error("Please specify a top-level module using the 'wt.top()' function")
    if not self.rst_net:
      util.error("Please specify a top-level reset net using the 'wt.rst()' function.")
    if not self.clk_net:
      util.error("Please specify a top-level clock net using the 'wt.clk()' function.")

    # build up a hierarchical data structure of all the modules and nets
    self._build_data_structure()

    print "\nDebug Net Hierarchy"
    print "-------------------"
    self.top_level.print_tree(0)

    print "\nGenerating modified HDL files..."
    self.top_level.locate_items()
    self.top_level.generate_hdl(self._wt_instantiation(), self.debug_files)
    print "\nSee '%s' for modified verilog files.\n" % OUTPUT_DIR

    self.generate_signal_list()

  def get_debug_files(self):
    return self.debug_files
