#!/usr/bin/env python3
"""Diff PMIC register dumps: mainline regmap ('c000: 01') vs TWRP spmi debugfs
('2c000 01 02 ...'). Usage: pmic-diff.py <sid>  (run from ~/oneplus2)"""
import sys, re
sid = int(sys.argv[1])
ml = {}
for l in open(f'logs/pmic/mainline-sid{sid}.txt'):
    m = re.match(r'^([0-9a-f]+): ([0-9a-f]+)', l.strip())
    if m: ml[int(m.group(1), 16)] = int(m.group(2), 16)
tw = {}
for l in open(f'logs/pmic/twrp-sid{sid}.raw'):
    p = l.split()
    if len(p) < 2: continue
    try: a = int(p[0], 16) & 0xffff
    except ValueError: continue
    for i, v in enumerate(p[1:17]):
        tw[a + i] = int(v, 16)
per = {}
for r in range(0x10000):
    if r in ml and r in tw and ml[r] != tw[r]:
        per.setdefault(r >> 8, []).append(r)
skip = (0x10, 0x11, 0x12, 0x13, 0x14, 0x15, 0x16)  # interrupt status/latched/etc offsets
for p, regs in sorted(per.items()):
    t, st = tw.get((p << 8) | 4, 0), tw.get((p << 8) | 5, 0)
    if t == 0 and st == 0: continue
    regs = [r for r in regs if (r & 0xff) not in (0x08, 0x09, 0x0a) + skip]
    if not regs: continue
    d = ' '.join(f'{r & 0xff:02x}:{ml[r]:02x}->{tw[r]:02x}' for r in regs[:12])
    print(f'sid{sid} 0x{p:02x}00 type {t:02x}/{st:02x}: {len(regs)} diff  (mainline->twrp) {d}')
