#!/usr/bin/env python3
"""Decode LK (aboot) DSI panel command tables: arrays of {u32 size, u32 ptr,
u32 wait_ms}; payload = [data0 data1 dtype flags] (+ long payload).
Usage: lk-panel-cmds.py aboot.img [must-contain-hex]"""
import struct, sys
d = open(sys.argv[1], 'rb').read()
need = bytes.fromhex(sys.argv[2]) if len(sys.argv) > 2 else None
e_phoff, = struct.unpack_from('<I', d, 0x1c)
e_phnum, = struct.unpack_from('<H', d, 0x2c)
segs = []
for i in range(e_phnum):
    typ, off, va, pa, fsz, msz = struct.unpack_from('<6I', d, e_phoff + i * 32)
    if typ == 1:
        segs.append((va, off, fsz))
def v2o(va):
    for s, o, n in segs:
        if s <= va < s + n:
            return o + va - s
    return None
def entry(o):
    size, ptr, wait = struct.unpack_from('<3I', d, o)
    if not (4 <= size <= 256 and size % 4 == 0 and wait < 1000): return None
    po = v2o(ptr)
    if po is None: return None
    p = d[po:po + size]
    dt = p[2]
    if dt not in (0x05, 0x15, 0x39, 0x29, 0x03, 0x13, 0x23, 0x37, 0x06): return None
    return size, p, wait
seen = set()
for o in range(0, len(d) - 12, 4):
    if o in seen: continue
    run = []; q = o
    while True:
        e = entry(q)
        if not e: break
        run.append((q, e)); q += 12
    if len(run) >= 8:
        for q, _ in run: seen.add(q)
        blob = b''.join(e[1] for _, e in run)
        if need and need not in blob: continue
        print(f'# table at file offset 0x{o:x}, {len(run)} commands')
        for q, (size, p, wait) in run:
            dt = p[2]
            if dt in (0x39, 0x29):
                n = p[0] | (p[1] << 8); data = p[4:4 + n]
            else:
                data = p[0:2] if dt not in (0x05,) else p[0:1] + b'\0'
            print(f'{dt:02x} {wait:3d} ' + ' '.join(f'{x:02x}' for x in data))
