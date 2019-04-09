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
"""Register access helper functions for apb_master simulation module"""

def reg_wr(fp, base, addr, data, comment=""):
  print >> fp, "WR %08x %08x" % (base + (addr<<2), data),
  if comment != "":
    print >> fp, " # %s" % (comment)
  else:
    print >> fp, ""

def reg_rd(fp, base, addr, expected, comment=""):
  print >> fp, "RD %08x %08x" % (base + (addr<<2), expected),
  if comment != "":
    print >> fp, " # %s" % (comment)
  else:
    print >> fp, ""

def reg_poll(fp, base, addr, expected, comment=""):
  print >> fp, "RP %08x %08x" % (base + (addr<<2), expected),
  if comment != "":
    print >> fp, " # %s" % (comment)
  else:
    print >> fp, ""

def wait_irq(fp, num, comment=""):
  print >> fp, "WT %d" % num,
  if comment != "":
    print >> fp, "                 # %s" % comment
  else:
    print >> fp, ""

def stall(fp, cycles, comment=""):
  print >> fp, "ST %d" % cycles,
  if comment != "":
    print >> fp, "               # %s" % comment
  else:
    print >> fp, ""
