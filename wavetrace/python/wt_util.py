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
"""Wavetrace utility functions"""
import re
import sys
import math

def error(message):
  """Prints an error message and exits."""
  sys.stderr.write("Error: %s\n" % message)
  sys.exit(1)

def net_name(net_string):
  """Extracts the net name from a net string
  Args:
    net_string: a net string containing a name and range, for example
                "data[3:0]" or "state[0]"
  Returns:
    the name the net (without the range part of the string)
  """
  return net_string.split('[')[0]


def net_width(net_string):
  """Extracts the bit-width from a net string
  Args:
    net_string: a net string containing a name and range, for example
                "data[3:0]" or "state[0]"
  Returns:
    An integer containing the bit-width of the signal
  """
  (hi, lo) = net_range(net_string)
  return abs(hi - lo) + 1

def net_range(net_string):
  """Extracts the range from a net string
  Args:
    net_string: a net string containing a name and range, for example
                "data[3:0]" or "state[0]"
  Returns:
    A pair of integers (high-bit, low-bit) making up the range
  """
  re_res = re.search(r'\[(.*?)\]', net_string)
  width = 0
  if re_res:
    range_str  = re_res.group(0)
    range_nums = range_str[1:-1].split(':')
    if len(range_nums) == 1:
      return (int(range_nums[0]), int(range_nums[0]))
    else:
      return (int(range_nums[0]), int(range_nums[1]))
  else:
    return (0,0)

def clog2(num):
  return int(math.ceil(math.log(num,2)))
