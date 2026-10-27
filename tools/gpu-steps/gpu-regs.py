#!/usr/bin/env python3
"""gpu-regs: read A4xx status registers (GPU at 0xfdb00000) through /dev/mem.
Only while the GPU is powered (power/control=on), or the read hangs the bus."""
import mmap
import sys, os, struct
REGS = {"RBBM_STATUS": 0x191, "RBBM_INT_0_STATUS": 0x17d, "RBBM_AHB_ERROR_STATUS": 0x18f,
        "CP_RB_BASE": 0x200, "CP_RB_RPTR": 0x204, "CP_RB_WPTR": 0x205,
        "CP_IB1_BASE": 0x206, "CP_IB1_BUFSZ": 0x207, "CP_IB2_BASE": 0x208,
        "CP_IB2_BUFSZ": 0x209, "CP_HW_FAULT": 0x4d8, "CP_PROTECT_STATUS": 0x4da,
        "VBIF_VERSION": 0x3000, "VBIF_CLKON": 0x3001, "VBIF_GATE_OFF_WRREQ_EN": 0x302a,
        "VBIF_IN_RD_LIM_CONF0": 0x302c, "VBIF_IN_WR_LIM_CONF0": 0x3030,
        "VBIF_XIN_HALT_CTRL0": 0x3080, "VBIF_XIN_HALT_CTRL1": 0x3081}
# read only with the argument "power" (not yet known to be safe to read on a hung GPU)
POWER = {"RBBM_CLOCK_CTL": 0x20, "RBBM_POWER_CNTL_IP": 0x98, "RBBM_SP_REGFILE_SLEEP_CNTL_0": 0x99,
         "RBBM_POWER_STATUS": 0x1b0, "CP_DEBUG": 0x22e}
if "power" in sys.argv[1:]:
    REGS = POWER
f = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
m = mmap.mmap(f, 0x4000 * 4, mmap.MAP_SHARED, mmap.PROT_READ, offset=0xfdb00000)
print(" ".join(f"{k}={struct.unpack('<I', m[4*v:4*v+4])[0]:#010x}" for k, v in REGS.items()), flush=True)
