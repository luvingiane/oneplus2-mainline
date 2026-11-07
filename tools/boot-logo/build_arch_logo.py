#!/usr/bin/env python3
"""Arch Linux logo in the OnePlus 2's boot screen (LOGO partition), in place.

Works on the REAL dump (backups/logo-A.img): image 0 of the container ("fhd_oppo_1080_1920_result.raw", OnePlus mark and
"POWERED BY android" on black) is replaced inside its own slot, so no other offset in the container changes.
The container has 28 header offsets, 14 of them empty, and two sets (1080x1920 and 1440x2559), which is why
boot_logo.py (written on a synthetic fixture) cannot parse it.

  build_arch_logo.py DUMP OUT_DIR [--variant a|b|both] [--logo PNG]
    a  OnePlus mark kept, the Arch logo where "powered by android" was
    b  only the Arch logo, centred
Writes OUT_DIR/logo-arch-{a,b}.img (16 MiB, flashable with `fastboot flash logo`) and a .png preview of each.
Payload format: RLE of bytes, pairs (value, count 1..255), over BGR888 pixels (see README.md).
"""
import argparse
import os
import struct
import sys

from PIL import Image

HDR = 512             # image 0 owns [0, offsets[1]): 0xf000 on A, 0x10000 on B (read from the dump)


def rle_decode(p):
    out = bytearray()
    for i in range(0, len(p) - 1, 2):
        out += bytes([p[i]]) * p[i + 1]
    return bytes(out)


def rle_encode(raw):
    out = bytearray()
    i, n = 0, len(raw)
    while i < n:
        v = raw[i]
        j = i
        while j < n and raw[j] == v and j - i < 255:
            j += 1
        out += bytes([v, j - i])
        i = j
    return bytes(out)


def image0(data):
    magic = data[:8]
    if magic != b"SPLASH!!":
        sys.exit("not a LOGO dump (magic %r)" % magic)
    w, h, length, special = struct.unpack_from("<4I", data, 0x20)
    if (w, h) != (1080, 1920):
        sys.exit("image 0 is %dx%d, expected 1080x1920" % (w, h))
    slot = struct.unpack_from("<I", data, 0x30 + 4)[0]
    if slot % 512 or not (0x8000 <= slot <= 0x20000) or HDR + length > slot:
        sys.exit("implausible slot for image 0: image 1 at 0x%x, payload %d" % (slot, length))
    if data[slot:slot + 8] != b"SPLASH!!":
        sys.exit("no SPLASH!! header at image 1 (0x%x)" % slot)
    raw = rle_decode(data[HDR:HDR + length])
    if len(raw) != w * h * 3:
        sys.exit("image 0 decodes to %d bytes, expected %d" % (len(raw), w * h * 3))
    return w, h, length, raw, slot


def to_image(w, h, bgr):
    rgb = bytearray(len(bgr))
    rgb[0::3] = bgr[2::3]
    rgb[1::3] = bgr[1::3]
    rgb[2::3] = bgr[0::3]
    return Image.frombytes("RGB", (w, h), bytes(rgb))


def to_bgr(img):
    rgb = img.convert("RGB").tobytes()
    bgr = bytearray(len(rgb))
    bgr[0::3] = rgb[2::3]
    bgr[1::3] = rgb[1::3]
    bgr[2::3] = rgb[0::3]
    return bytes(bgr)


def logo_scaled(path, width, levels):
    lg = Image.open(path).convert("RGBA")
    # crop to the drawn pixels, so the centring is of the logo and not of its transparent margin
    lg = lg.crop(lg.getbbox())
    h = round(lg.height * width / lg.width)
    lg = lg.resize((width, h), Image.LANCZOS)
    if levels > 0:
        # the RLE is by byte: every extra grey on an edge is one more run. 1 level = pure white on black
        a = lg.getchannel("A").point(lambda v: round(v * levels / 255) * 255 // levels)
        lg.putalpha(a)
    return lg


def compose(variant, orig, logo_png, width, levels):
    img = orig.copy()
    if variant == "a":
        # "POWERED BY android" is in the bottom ~230 rows: black over it, the Arch logo in its place
        img.paste((0, 0, 0), (0, 1690, 1080, 1920))
        lg = logo_scaled(logo_png, width or 460, levels)
        img.paste(lg, ((1080 - lg.width) // 2, 1790 - lg.height // 2), lg)
    else:
        img = Image.new("RGB", (1080, 1920), (0, 0, 0))
        lg = logo_scaled(logo_png, width or 660, levels)
        img.paste(lg, ((1080 - lg.width) // 2, (1920 - lg.height) // 2), lg)
    return img


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("dump")
    ap.add_argument("out_dir")
    ap.add_argument("--variant", default="both", choices=["a", "b", "both"])
    ap.add_argument("--width", type=int, default=0, help="logo width in pixels (default 460 for a, 660 for b)")
    ap.add_argument("--levels", type=int, default=1, help="grey levels on the logo's edges (1 = none: white on black)")
    ap.add_argument("--logo", default=os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "build",
                                                    "boot-logo", "archlinux-logo-light-1200dpi.png"))
    a = ap.parse_args()
    data = open(a.dump, "rb").read()
    w, h, length, raw, SLOT = image0(data)
    orig = to_image(w, h, raw)
    os.makedirs(a.out_dir, exist_ok=True)
    for v in (["a", "b"] if a.variant == "both" else [a.variant]):
        img = compose(v, orig, a.logo, a.width, a.levels)
        payload = rle_encode(to_bgr(img))
        room = SLOT - HDR
        print("variant %s: payload %d bytes (original %d, room %d)" % (v, len(payload), length, room))
        if len(payload) > room:
            sys.exit("variant %s does not fit its slot (%d > %d): make the logo smaller" % (v, len(payload), room))
        assert rle_decode(payload) == to_bgr(img)
        out = bytearray(data)
        struct.pack_into("<I", out, 0x28, len(payload))
        out[HDR:SLOT] = payload + b"\0" * (room - len(payload))
        assert len(out) == len(data) == 16 * 1024 * 1024
        assert out[SLOT:] == data[SLOT:]
        # nothing but image 0's payload and its length field may differ
        diff = [i for i in range(0, SLOT) if out[i] != data[i] and not (0x28 <= i < 0x2C or HDR <= i < SLOT)]
        assert not diff, "header bytes changed: %r" % diff[:8]
        path = os.path.join(a.out_dir, "logo-arch-%s.img" % v)
        open(path, "wb").write(out)
        img.save(os.path.join(a.out_dir, "logo-arch-%s.png" % v))
        print("  ->", path)


main()
