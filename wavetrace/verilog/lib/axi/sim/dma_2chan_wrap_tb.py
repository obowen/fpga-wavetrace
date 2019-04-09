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
STRM_DATA_BITS = 32
MEM_DATA_BITS = 64
RATIO = MEM_DATA_BITS / STRM_DATA_BITS

fp_in  = open("in.dat",  "w")
fp_ref = open("ref.dat", "w")
fp_cfg = open("cfg.dat", "w")

lengths = [512, 101,  300,  407,  61,    222]   # keep even number of frames
bursts  = [16,  11,   1,    9,    4,     5]

# set byte addresses based on lengths of transfers
a = 8
addrs = []
for i in xrange(len(lengths)):
    addrs.append(a)
    a += lengths[i]*8

DMA_WR_BASE = (0)
DMA_RD_BASE = (1 << 31)

START_ADDR = 0
LEN_ADDR   = 1
BURST_ADDR = 2
VLD_ADDR   = 3
IRQ_ADDR   = 7

def reg_wr(base, addr, data, comment=""):
    print >> fp_cfg, "WR %08x %08x" % (base + (addr<<2), data),
    if comment != "":
        print >> fp_cfg, " # %s" % (comment)
    else:
        print >> fp_cfg, ""

def reg_rd(base, addr, expected, comment=""):
    print >> fp_cfg, "RD %08x %08x" % (base + (addr<<2), expected),
    if comment != "":
        print >> fp_cfg, " # %s" % (comment)
    else:
        print >> fp_cfg, ""

def wait_irq(num, comment):
    print >> fp_cfg, "WT %d" % num,
    if comment != "":
        print >> fp_cfg, "                 # %s" % comment
    else:
        print >> fp_cfg, ""


for f in xrange(0, len(lengths), 1):
    # put length at start of each frame to test the DMA blocks in a
    # 'length-in-stream' mode, this is added to the first two bytes of the first
    # memory word
    first_word = [(lengths[f]*8) & 0xFF, ((lengths[f]*8) >> 8) & 0xFF] + [0]*6
    for i in range(RATIO):
        d = 0
        for j in range(STRM_DATA_BITS/8):
            d += (first_word[i*STRM_DATA_BITS/8 + j]) << j*8
        print >> fp_in,  "%d 0" % d
        print >> fp_ref, "%d 0" % d

    len_remain = lengths[f]-1
    for i in range(RATIO * len_remain):
        d = i % (1 << STRM_DATA_BITS)
        eof = 1 if (i==RATIO*len_remain-1) else 0
        print >> fp_in, "%d %d" % (d, eof)
        print >> fp_ref, "%d %d" % (d, eof)

for f in xrange(0, len(lengths), 2):
    # write config
    reg_wr(DMA_WR_BASE, START_ADDR, addrs[f],   "write frame %d"%f)
    reg_wr(DMA_WR_BASE, LEN_ADDR,   0)#lengths[f])
    reg_wr(DMA_WR_BASE, BURST_ADDR, bursts[f])
    reg_wr(DMA_WR_BASE, VLD_ADDR,   1)

    # write config
    reg_wr(DMA_WR_BASE, START_ADDR, addrs[f+1],   "write frame %d"%(f+1))
    reg_wr(DMA_WR_BASE, LEN_ADDR,   0)#lengths[f+1])
    reg_wr(DMA_WR_BASE, BURST_ADDR, bursts[f+1])
    reg_wr(DMA_WR_BASE, VLD_ADDR,   1)

    wait_irq(0, "wait for writer (frame %d)" % (f))
    reg_wr(DMA_WR_BASE, IRQ_ADDR, 0, "clear writer irq")
    wait_irq(0, "wait for writer (frame %d)" % (f+1))
    reg_wr(DMA_WR_BASE, IRQ_ADDR, 0, "clear writer irq")

    # read config
    reg_wr(DMA_RD_BASE, START_ADDR, addrs[f],   "read frame %d"%f)
    reg_wr(DMA_RD_BASE, LEN_ADDR,   lengths[f])
    reg_wr(DMA_RD_BASE, BURST_ADDR, bursts[f])
    reg_wr(DMA_RD_BASE, VLD_ADDR,   1)

    # read config
    reg_wr(DMA_RD_BASE, START_ADDR, addrs[f+1],   "read frame %d"%(f+1))
    reg_wr(DMA_RD_BASE, LEN_ADDR,   lengths[f+1])
    reg_wr(DMA_RD_BASE, BURST_ADDR, bursts[f+1])
    reg_wr(DMA_RD_BASE, VLD_ADDR,   1)

    wait_irq(1, "wait for reader (frame %d)" % (f))
    reg_wr(DMA_RD_BASE, IRQ_ADDR, 0, "clear readerirq")
    wait_irq(1, "wait for reader (frame %d)" % (f))
    reg_wr(DMA_RD_BASE, IRQ_ADDR, 0, "clear readerirq")

fp_in.close()
fp_ref.close()
fp_cfg.close()
