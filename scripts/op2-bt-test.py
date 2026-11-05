# OnePlus 2: prova Bluetooth da Python (raw HCI): versione locale e scansione classica (conta i dispositivi, non stampa indirizzi).
# Su un controller senza BD address valido serve prima impostarne uno (mgmt SET_PUBLIC_ADDRESS, 0x0039): il controller si reinizializza.
import socket, struct, time, select, fcntl
try:
    t = socket.socket(31, socket.SOCK_RAW, 1)
    fcntl.ioctl(t, 0x400448C9, 0)   # HCIDEVUP
    print("HCIDEVUP ok")
except OSError as e:
    print("HCIDEVUP:", e)
s = socket.socket(31, socket.SOCK_RAW, 1)
s.bind((0, 0))
s.setsockopt(0, 2, struct.pack("<IIIHH", 0xffffffff, 0xffffffff, 0xffffffff, 0, 0))
def run(op, params, secs):
    s.send(struct.pack("<BHB", 1, op, len(params)) + params)
    out = []; end = time.time() + secs
    while time.time() < end:
        r, _, _ = select.select([s], [], [], 0.5)
        if r:
            out.append(s.recv(512))
    return out
for e in run(0x1001, b"", 2):
    if len(e) > 14 and e[1] == 0x0e and e[4:6] == b"\x01\x10":
        st, hv, hr, lv, man, lsv = struct.unpack("<BBHBHH", e[6:15])
        print(f"read local version: status {st} hci_ver {hv} lmp {lv} manufacturer {man} (29 = Qualcomm)")
found = set(); n = 0
for e in run(0x0401, bytes([0x33, 0x8b, 0x9e, 8, 0]), 12):
    n += 1
    if len(e) > 3 and e[1] in (0x02, 0x22):
        sz = 6 if e[1] == 0x02 else 14
        for i in range(e[3]):
            found.add(e[4 + sz * i:10 + sz * i])
    if len(e) > 3 and e[1] == 0x2f:
        found.add(e[4:10])
print("eventi:", n, "- dispositivi Bluetooth classico trovati:", len(found))
