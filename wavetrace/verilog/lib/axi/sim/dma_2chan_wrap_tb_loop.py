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

fp_cfg = open("cfg.dat", "w")

# all sizes in WORDS
lengths  = [600, 101,  300,  407,  61,    222]   # keep even number of frames
bursts   = [16,  11,   1,    9,    4,     5]

DMA_WR_BASE = (0)
DMA_RD_BASE = (1 << 31)

START_ADDR = 0
LEN_ADDR   = 1
BURST_ADDR = 2
VLD_ADDR   = 3
IRQ_ADDR   = 7

rd_addr = []
wr_addr = []
a = 0
for i in range(len(lengths)):
    rd_addr.append(a)
    wr_addr.append(a + lengths[i])
    a += 2*lengths[i]

print rd_addr
print wr_addr


#memory init file
MEM_ADDR_BITS = 14
fp_mem_init = open("meminit.dat", "w")
fp_mem_ref  = open("memref.dat", "w")

dr8 = 0
for a in range(2**MEM_ADDR_BITS):
    d64 = 0
    for i in range(len(lengths)):
        if (a >= rd_addr[i] and a < rd_addr[i]+lengths[i]):
            for j in range(8):
                d64 += (dr8 << (8*j))
                dr8  = (dr8+1)%256

    print >> fp_mem_init, "%016x" % d64
fp_mem_init.close()

# memory reference file
dr8 = 0
dw8 = 0
for a in range(2**MEM_ADDR_BITS):
    d64 = 0
    for i in range(len(lengths)):
        if (a >= rd_addr[i] and a < rd_addr[i]+lengths[i]):
            for j in range(8):
                d64 += (dr8 << (8*j))
                dr8  = (dr8+1)%256

        elif (a >= wr_addr[i] and a < wr_addr[i]+lengths[i]):
            for j in range(8):
                d64 += (dw8 << (8*j))
                dw8  = (dw8+1)%256

    print >> fp_mem_ref, "%016x" % d64
fp_mem_ref.close()


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


for f in xrange(0, len(lengths), 2):

    # read config
    reg_wr(DMA_RD_BASE, START_ADDR, 8*rd_addr[f],   "read frame %d"%f)
    reg_wr(DMA_RD_BASE, LEN_ADDR,   lengths[f])
    reg_wr(DMA_RD_BASE, BURST_ADDR, bursts[f])
    reg_wr(DMA_RD_BASE, VLD_ADDR,   1)

    # read config
    reg_wr(DMA_RD_BASE, START_ADDR, 8*rd_addr[f+1],   "read frame %d"%(f+1))
    reg_wr(DMA_RD_BASE, LEN_ADDR,   lengths[f+1])
    reg_wr(DMA_RD_BASE, BURST_ADDR, bursts[f+1])
    reg_wr(DMA_RD_BASE, VLD_ADDR,   1)


    # write config
    reg_wr(DMA_WR_BASE, START_ADDR, 8*wr_addr[f],   "write frame %d"%f)
    reg_wr(DMA_WR_BASE, LEN_ADDR,   lengths[f])
    reg_wr(DMA_WR_BASE, BURST_ADDR, bursts[f])
    reg_wr(DMA_WR_BASE, VLD_ADDR,   1)

    # write config
    reg_wr(DMA_WR_BASE, START_ADDR, 8*wr_addr[f+1],   "write frame %d"%(f+1))
    reg_wr(DMA_WR_BASE, LEN_ADDR,   lengths[f+1])
    reg_wr(DMA_WR_BASE, BURST_ADDR, bursts[f+1])
    reg_wr(DMA_WR_BASE, VLD_ADDR,   1)

    wait_irq(1, "wait for reader (frame %d)" % (f))
    reg_wr(DMA_RD_BASE, IRQ_ADDR, 0, "clear readerirq")
    wait_irq(1, "wait for reader (frame %d)" % (f))
    reg_wr(DMA_RD_BASE, IRQ_ADDR, 0, "clear readerirq")

    wait_irq(0, "wait for writer (frame %d)" % (f))
    reg_wr(DMA_WR_BASE, IRQ_ADDR, 0, "clear writer irq")
    wait_irq(0, "wait for writer (frame %d)" % (f+1))
    reg_wr(DMA_WR_BASE, IRQ_ADDR, 0, "clear writer irq")

fp_cfg.close()
