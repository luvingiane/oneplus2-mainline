import re, struct, sys
G = "/home/matt/oneplus2/build/linux-7.3/drivers/gpu/drm/msm/generated/"
regs = {}
for l in open(G + "a4xx.xml.h"):
    m = re.match(r"#define REG_A4XX_(\w+)\s+0x([0-9a-f]+)\s*$", l)
    if m: regs[int(m.group(2), 16)] = m.group(1)
ops = {}
for l in open(G + "adreno_pm4.xml.h"):
    m = re.match(r"\s*(CP_\w+)\s*=\s*(\d+),", l)
    if m: ops.setdefault(int(m.group(2)), m.group(1))
d = open(sys.argv[1], "rb").read()
bufs, cmds, i = {}, [], 0
pending = None
while i + 8 <= len(d):
    t, sz = struct.unpack_from("<II", d, i); body = d[i + 8:i + 8 + sz]; i += 8 + sz
    if t == 3:   # RD_GPUADDR: iova lo, size, iova hi
        lo, size = struct.unpack_from("<II", body); hi = struct.unpack_from("<I", body, 8)[0] if len(body) >= 12 else 0
        pending = (hi << 32) | lo
    elif t == 12 and pending is not None:
        bufs[pending] = body; pending = None
    elif t == 6:  # RD_CMDSTREAM_ADDR: iova lo, sizedwords, hi
        lo, n = struct.unpack_from("<II", body); hi = struct.unpack_from("<I", body, 8)[0] if len(body) >= 12 else 0
        cmds.append(((hi << 32) | lo, n))
print("buffers:", len(bufs), "cmdstreams:", [(hex(a), n) for a, n in cmds])
want = int(sys.argv[2], 16) if len(sys.argv) > 2 else cmds[-1][0]
def find(addr):
    for b, data in bufs.items():
        if b <= addr < b + len(data): return data[addr - b:]
    return None
def decode(addr, ndw, depth=0):
    data = find(addr)
    if data is None: print("  " * depth + f"<{addr:#x} not captured>"); return
    w = struct.unpack_from(f"<{ndw}I", data); k = 0
    while k < ndw:
        h = w[k]; typ = h >> 30
        if typ == 0:
            cnt = ((h >> 16) & 0x3fff) + 1; reg = h & 0x7fff
            for j in range(cnt):
                print("  " * depth + f"{k:3d} W {regs.get(reg + j, hex(reg + j))} = {w[k + 1 + j]:#010x}")
            k += 1 + cnt
        elif typ == 3:
            cnt = ((h >> 16) & 0x3fff) + 1; op = (h >> 8) & 0xff
            args = w[k + 1:k + 1 + cnt]
            print("  " * depth + f"{k:3d} {ops.get(op, hex(op))} " + " ".join(f"{a:#x}" for a in args[:8]) + (" ..." if cnt > 8 else ""))
            if ops.get(op) in ("CP_INDIRECT_BUFFER_PFE", "CP_INDIRECT_BUFFER_PFD", "CP_INDIRECT_BUFFER") and depth < 2:
                decode(args[0], args[1], depth + 1)
            k += 1 + cnt
        elif typ == 2:
            k += 1
        else:
            print("  " * depth + f"{k:3d} ?? {h:#x}"); k += 1
for a, n in cmds:
    if a == want or len(sys.argv) <= 2:
        print(f"=== cmdstream {a:#x} ({n} dwords)"); decode(a, n)
