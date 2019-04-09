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
STRM_DATA_BITS = 8
MEM_DATA_BITS = 64
RATIO = MEM_DATA_BITS / STRM_DATA_BITS
PORTS  = 2
FRAMES = 16
LENGTH = 100

START_ADDR = 0*4
LEN_ADDR   = 1*4
BURST_ADDR = 2*4
GO_ADDR    = 3*4
IRQ_ADDR   = 7*4

for p in range(PORTS):
    prefix = "%03d" % p
    fp_in   = open("in"  +prefix+".dat", "w")
    fp_ref  = open("ref" +prefix+".dat", "w")
    fp_wcfg = open("wcfg"+prefix+".dat", "w")
    fp_rcfg = open("rcfg"+prefix+".dat", "w")
    for f in range(FRAMES):
        for i in range(RATIO*LENGTH):
            d = ((p+1)*i) % (1 << 8)
            eof = 1 if (i==RATIO*LENGTH-1) else 0
            print >> fp_in,  "%d" % d
            print >> fp_ref, "%d %d" % (d, eof)

        print >> fp_wcfg, "# Write Frame %d"      % f
        print >> fp_wcfg, "WR %08x %08x # dest"   % (START_ADDR, p*FRAMES*LENGTH*RATIO + f*LENGTH*RATIO)
        print >> fp_wcfg, "WR %08x %08x # len"    % (LEN_ADDR,  LENGTH)
        print >> fp_wcfg, "WR %08x %08x # burst"  % (BURST_ADDR, (f%16)+1)
        print >> fp_wcfg, "WR %08x %08x # go"     % (GO_ADDR, 1)
        print >> fp_wcfg, "WR %08x %08x # stop"   % (GO_ADDR, 0)
        if (f > 0):
            print >> fp_wcfg, "WT 1                 # wait reader frame %d" % (f-1)
        print >> fp_wcfg, "WT 0                 # wait writer frame %d" % f
        print >> fp_wcfg, "WR %08x %08x # clear irq" % (IRQ_ADDR, 0)


        print >> fp_rcfg, "WT 0                 # wait writer frame %d" % (f)
        print >> fp_rcfg, "# Read Frame %d" % (f)
        print >> fp_rcfg, "WR %08x %08x # dest"   % (START_ADDR, p*FRAMES*LENGTH*RATIO + f*LENGTH*RATIO)
        print >> fp_rcfg, "WR %08x %08x # len"    % (LEN_ADDR,  LENGTH)
        print >> fp_rcfg, "WR %08x %08x # burst"  % (BURST_ADDR, (f%16)+1)
        print >> fp_rcfg, "WR %08x %08x # go"     % (GO_ADDR, 1)
        print >> fp_rcfg, "WR %08x %08x # stop"   % (GO_ADDR, 0)
        print >> fp_rcfg, "WT 1                 # wait reader frame %d" % (f)
        print >> fp_rcfg, "WR %08x %08x # clear irq" % (IRQ_ADDR, 0)

    fp_in.close()
    fp_ref.close()
    fp_wcfg.close()
    fp_rcfg.close()

