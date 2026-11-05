# OnePlus 2: impulso di vibrazione dal dispositivo FF "op2-pmi8994-haptic" (uso: python3 op2-vibe-test.py [ms] [intensita 0-65535]).
import fcntl, glob, os, struct, sys, time
ms = int(sys.argv[1]) if len(sys.argv) > 1 else 300
mag = int(sys.argv[2]) if len(sys.argv) > 2 else 40000
dev = None
for n in glob.glob("/sys/class/input/input*/name"):
    if open(n).read().strip() == "op2-pmi8994-haptic":
        d = os.path.dirname(n)
        dev = "/dev/input/" + [x for x in os.listdir(d) if x.startswith("event")][0]
if not dev:
    sys.exit("dispositivo haptic non trovato")
fd = os.open(dev, os.O_RDWR)
# struct ff_effect (aarch64, 48 byte): type, id, direction, trigger{button,interval}, replay{length,delay}, pad, union{rumble: strong, weak}
eff = struct.pack("<HhHHHHH2xHH", 0x50, -1, 0, 0, 0, ms, 0, mag, mag).ljust(48, b"\0")
buf = bytearray(eff)
fcntl.ioctl(fd, 0x40304580, buf)            # EVIOCSFF
eid = struct.unpack_from("<h", buf, 2)[0]
os.write(fd, struct.pack("llHHi", 0, 0, 0x15, eid, 1))   # EV_FF play
print(f"vibrazione avviata ({dev}, effetto {eid}, {ms} ms, intensita {mag})")
time.sleep(ms / 1000 + 0.2)
os.write(fd, struct.pack("llHHi", 0, 0, 0x15, eid, 0))
fcntl.ioctl(fd, 0x40044581, eid)            # EVIOCRMFF
