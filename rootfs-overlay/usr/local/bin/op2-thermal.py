#!/usr/bin/env python3
# OnePlus 2: limite termico a mano, versione Python (rootfs con python3 e senza devmem: B/ztOS).
# Stessa logica di op2-thermal (sh): legge i 16 sensori TSENS (0xfc4a8000+0x1044+4*n, codice bit 11:0)
# e cambia a gradini il post-divisore dei PLL (USER_CTL[9:8]: 0xf9015010 A53, 0xf9016010 A57; 0=/1 1=/2 3=/4).
# Livello 0 = come all'avvio; 1 = A57 /4 (se presenti) e A53 almeno /2; 2 = A53 e A57 /4.
# Il cluster A57 non viene mai toccato se cpu4 non esiste. Variabili: OP2_THERMAL_HI/LO/CRIT/OFF/DT.
import mmap, os, struct, sys, time

HI = int(os.environ.get("OP2_THERMAL_HI", 770))
LO = int(os.environ.get("OP2_THERMAL_LO", 735))
CRIT = int(os.environ.get("OP2_THERMAL_CRIT", 800))
OFF = int(os.environ.get("OP2_THERMAL_OFF", 805))
DT = float(os.environ.get("OP2_THERMAL_DT", 1))
LOG = os.environ.get("OP2_THERMAL_LOG", "/run/op2-thermal.log")
A53, A57 = 0xF9015010, 0xF9016010

fd = os.open("/dev/mem", os.O_RDWR | os.O_SYNC)
pages = {}
def page(addr):
    base = addr & ~0xFFF
    if base not in pages:
        pages[base] = mmap.mmap(fd, 0x1000, mmap.MAP_SHARED, mmap.PROT_READ | mmap.PROT_WRITE, offset=base)
    return pages[base], addr & 0xFFF
def rd(addr):
    m, o = page(addr)
    return struct.unpack("<I", m[o:o + 4])[0]
def wr(addr, v):
    m, o = page(addr)
    m[o:o + 4] = struct.pack("<I", v & 0xFFFFFFFF)
def tmax():
    return max(rd(0xFC4A8000 + 0x1044 + 4 * n) & 0xFFF for n in range(16))
def getdiv(a): return (rd(a) >> 8) & 3
def setdiv(a, d): wr(a, (rd(a) & ~0x300) | (d << 8))
def has57(): return os.path.isdir("/sys/devices/system/cpu/cpu4")

H57 = has57()
I53 = getdiv(A53)
I57 = getdiv(A57) if H57 else 0
def apply(lvl):
    a, b = I53, I57
    if lvl == 1:
        a, b = max(a, 1), 3
    elif lvl == 2:
        a, b = 3, 3
    setdiv(A53, a)
    if H57 and has57():
        setdiv(A57, b)

lvl = 0
off = False
log = open(LOG, "a", buffering=1)
while True:
    t = tmax()
    n = lvl
    if t >= CRIT: n = 2
    elif t >= HI and lvl < 2: n = lvl + 1
    elif t <= LO and lvl > 0: n = lvl - 1
    if n != lvl:
        apply(n); lvl = n
    if H57 and not off and lvl == 2 and t >= OFF:
        for c in (7, 6, 5, 4):
            try: open(f"/sys/devices/system/cpu/cpu{c}/online", "w").write("0")
            except OSError: pass
        off = True
    up = open("/proc/uptime").read().split()[0]
    log.write(f"{up} code={t} lvl={lvl} a53={rd(A53):#x}" + (f" a57={rd(A57):#x}" if has57() else "") + "\n")
    time.sleep(DT)
