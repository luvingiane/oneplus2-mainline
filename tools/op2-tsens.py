#!/usr/bin/env python3
"""
op2-tsens: read the MSM8994 TSENS sensors in degrees C from userspace
(/dev/mem), with the 8994 fuse calibration of the OnePlus kernel
(drivers/thermal/msm8974-tsens.c: tsens_calib_8994_sensors,
tsens_tz_code_to_degc). Stopgap until a kernel tsens driver handles 8994.

  op2-tsens.py [interval_s]   one line per reading (all 16 sensors)

TSENS at 0xfc4a8000 (status of sensor n at +0x1030 + 4n, 10-bit code),
fuses at 0xfc4bc000. Primary fuse region only: if the redundant one is
selected, or calibration mode is not two-point, falls back to the
calibration-less defaults (point 532, slopes from the OnePlus DTS).
"""
import mmap
import os
import struct
import sys
import time

TSENS, FUSE = 0xfc4a8000, 0xfc4bc000
SLOPES = [2901, 2846] + [3200] * 14          # qcom,slope (OnePlus msm8994.dtsi)
FACTOR, P1, P2 = 1000, 30, 120               # TSENS_SLOPE_FACTOR, cal points


def rd(m, off):
    return struct.unpack("<I", m[off:off + 4])[0]


def calibration(fuse):
    redun = (rd(fuse, 0x464) & 0xe0000000) >> 29
    d0, d1, d2 = rd(fuse, 0xd0), rd(fuse, 0xd4), rd(fuse, 0xd8)
    mode = (d2 & 0x700000) >> 20
    if redun == 3 or mode != 3:
        why = "redundant fuses selected" if redun == 3 else f"calibration mode {mode}"
        sens = [(s, 532 * FACTOR - P1 * s) for s in SLOPES]
        return sens, f"calibration-less ({why})"
    base0 = d0 & 0x3ff
    base1 = (d0 & 0xffc00) >> 10
    pts = [(d0 >> 20) & 0xf, (d0 >> 24) & 0xf, (d0 >> 28) & 0xf,
           d1 & 0xf, (d1 >> 4) & 0xf, (d1 >> 8) & 0xf, (d1 >> 12) & 0xf,
           (d1 >> 16) & 0xf, (d1 >> 20) & 0xf, (d1 >> 24) & 0xf, (d1 >> 28) & 0xf,
           d2 & 0xf, (d2 >> 4) & 0xf, (d2 >> 8) & 0xf, (d2 >> 12) & 0xf, (d2 >> 16) & 0xf]
    slope = (base1 - base0) * FACTOR // (P2 - P1)
    sens = [(slope, (base0 + p) * FACTOR - P1 * slope) for p in pts]
    return sens, f"two-point (base0 {base0}, base1 {base1})"


def degc(code, slope, offset):
    num = code * FACTOR - offset
    return round(num / slope, 1) if slope else None


def main():
    interval = float(sys.argv[1]) if len(sys.argv) > 1 else 0
    f = os.open("/dev/mem", os.O_RDONLY | os.O_SYNC)
    ts = mmap.mmap(f, 0x2000, mmap.MAP_SHARED, mmap.PROT_READ, offset=TSENS)
    fuse = mmap.mmap(f, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ, offset=FUSE)
    sens, how = calibration(fuse)
    print("calibration:", how, flush=True)
    while True:
        codes = [rd(ts, 0x1030 + 4 * n) & 0x3ff for n in range(16)]
        temps = [degc(c, *sens[n]) if c else None for n, c in enumerate(codes)]
        hot = max(t for t in temps if t is not None)
        print(time.strftime("%H:%M:%S"), "max", hot, "C |",
              " ".join("-" if t is None else f"{t:.0f}" for t in temps), flush=True)
        if not interval:
            break
        time.sleep(interval)


if __name__ == "__main__":
    main()
