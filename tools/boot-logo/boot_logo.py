#!/usr/bin/env python3
"""boot_logo.py — OnePlus 2 (MSM8994) boot logo tool: parse/build/verify the
LOGO partition image (logo.bin container) so the first boot screen can be
replaced (task 362: Arch Linux logo instead of "Powered by Android").

Container format ("old" OnePlus/OPPO logo.bin encoding, used by OP2):
  - the LOGO partition image starts directly with image #0's 512-byte header
  - every image header (512 bytes, little endian):
      0x00  8 bytes  magic "SPLASH!!"
      0x08  24 bytes blank
      0x20  uint32   width
      0x24  uint32   height
      0x28  uint32   lengthOfData  (RLE payload bytes that follow the header)
      0x2C  uint32   special
      0x30  uint32   offsets[28]   (absolute file offsets of each image header;
                                    offsets[0] == 0; table ends at first 0)
      0xA0  64 bytes name (NUL-padded, e.g. "bootlogo.png")
      0xE0  288 bytes metadata
  - image payload starts at offsets[i] + 512, length = lengthOfData, padded
    with zeros up to a 512-byte boundary
  - payload = byte-oriented RLE over BGR888 pixels: pairs (value, count),
    count in 1..255; decoded size must equal width*height*3

Sources (see report.md): LogoInjector v1.52 by makers_mark @ XDA (IMAGEHEAD /
OFFSETSTART=48 / Decode / Encode), backward compatible with the OP2 encoding;
Qualcomm/OnePlus logo_gen.py (OnePlusOSS/android_device_qcom_common,
display/logo/logo_gen.py) for the SPLASH!! header family; LK splash partition
code in research/lk2nd (include/dev/fbcon.h:35-38, app/aboot/aboot.c:4986+).

Stdlib only (zlib/struct). numpy is used if importable, otherwise pure Python.
"""

import argparse
import hashlib
import re
import struct
import sys
import zlib

MAGIC = b"SPLASH!!"
HEADER_SIZE = 512          # iBlock
OFFSET_START = 48          # OFFSETSTART in LogoInjector
MAX_OFFSETS = 28           # IMAGEHEAD.offsets[28]
BPP = 3                    # BYTESPERPIXEL: BGR888

# ---------------------------------------------------------------- container

def parse_header(buf, off):
    if len(buf) < off + HEADER_SIZE:
        raise ValueError("header at 0x%x beyond EOF" % off)
    magic = bytes(buf[off:off + 8])
    if magic != MAGIC:
        raise ValueError("bad magic %r at 0x%x (expected %r)" % (magic, off, MAGIC))
    width, height, length, special = struct.unpack_from("<4I", buf, off + 0x20)
    offsets = list(struct.unpack_from("<%dI" % MAX_OFFSETS, buf, off + OFFSET_START))
    name = bytes(buf[off + 0xA0:off + 0xE0]).split(b"\0")[0]
    meta = bytes(buf[off + 0xE0:off + HEADER_SIZE])
    return {
        "off": off, "magic": magic, "width": width, "height": height,
        "length": length, "special": special, "offsets": offsets,
        "name": name.decode("latin1"), "meta": meta,
    }


def number_of_offsets(hdr0):
    # LogoInjector GetNumberOfOffsets: count entries until first 0 after idx 0
    n = 0
    for i, v in enumerate(hdr0["offsets"]):
        if v == 0 and i != 0:
            break
        n += 1
    return n


def parse_container(data):
    hdr0 = parse_header(data, 0)
    n = number_of_offsets(hdr0)
    if n < 1 or n > MAX_OFFSETS:
        raise ValueError("implausible image count %d" % n)
    offs = hdr0["offsets"][:n]
    if offs[0] != 0:
        raise ValueError("offsets[0] != 0 (got 0x%x)" % offs[0])
    images = []
    for i, off in enumerate(offs):
        if off % 1 and i > 0:
            pass
        if off + HEADER_SIZE > len(data):
            raise ValueError("image %d header at 0x%x beyond EOF" % (i, off))
        h = parse_header(data, off)
        data_off = off + HEADER_SIZE
        if data_off + h["length"] > len(data):
            raise ValueError("image %d payload at 0x%x beyond EOF" % (i, data_off))
        images.append({
            "index": i, "header": h,
            "header_raw": bytes(data[off:off + HEADER_SIZE]),
            "payload": bytes(data[data_off:data_off + h["length"]]),
        })
    return hdr0, images


def block_it(size, block=HEADER_SIZE):
    return size if size % block == 0 else size + (block - size % block)

# ------------------------------------------------------------------- RLE

def rle_encode(raw):
    """byte-oriented RLE: pairs (value, count), count in 1..255"""
    out = bytearray()
    i = 0
    n = len(raw)
    while i < n:
        v = raw[i]
        run = 1
        while i + run < n and run < 0xFF and raw[i + run] == v:
            run += 1
        out.append(v)
        out.append(run)
        i += run
    return bytes(out)


def rle_decode(data, expected):
    out = bytearray()
    i = 0
    while i + 1 < len(data) and len(out) < expected:
        v, count = data[i], data[i + 1]
        take = count if count else 0
        if len(out) + take > expected:
            take = expected - len(out)
        out.extend(bytes([v]) * take)
        i += 2
    if len(out) != expected:
        raise ValueError("RLE decode got %d bytes, expected %d" % (len(out), expected))
    return bytes(out)

# ------------------------------------------------------------------- PNG

def decode_png(path):
    """Minimal PNG decoder: 8-bit, color types 0/2/3/4/6, non-interlaced.
    Returns (w, h, rgba bytearray)."""
    d = open(path, "rb").read()
    if d[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG: %s" % path)
    pos = 8
    idat = bytearray()
    plte = b""
    w = h = bd = ct = inter = None
    while pos < len(d):
        (length,) = struct.unpack_from(">I", d, pos)
        ctype = d[pos + 4:pos + 8]
        chunk = d[pos + 8:pos + 8 + length]
        if ctype == b"IHDR":
            w, h, bd, ct, _comp, _filt, inter = struct.unpack(">IIBBBBB", chunk)
        elif ctype == b"PLTE":
            plte = chunk
        elif ctype == b"IDAT":
            idat.extend(chunk)
        elif ctype == b"IEND":
            break
        pos += 12 + length
    if bd != 8 or inter != 0 or ct not in (0, 2, 3, 4, 6):
        raise ValueError("unsupported PNG (bitdepth=%d colortype=%d interlace=%d)"
                         % (bd, ct, inter))
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ct]
    raw = zlib.decompress(bytes(idat))
    stride = w * channels
    if len(raw) < (stride + 1) * h:
        raise ValueError("PNG data short")
    # unfilter
    out = bytearray(h * stride)
    prev = bytearray(stride)
    p = 0
    for y in range(h):
        f = raw[p]
        p += 1
        row = bytearray(raw[p:p + stride])
        p += stride
        if f == 1:
            for x in range(channels, stride):
                row[x] = (row[x] + row[x - channels]) & 0xFF
        elif f == 2:
            for x in range(stride):
                row[x] = (row[x] + prev[x]) & 0xFF
        elif f == 3:
            for x in range(stride):
                a = row[x - channels] if x >= channels else 0
                row[x] = (row[x] + ((a + prev[x]) >> 1)) & 0xFF
        elif f == 4:
            for x in range(stride):
                a = row[x - channels] if x >= channels else 0
                b = prev[x]
                c = prev[x - channels] if x >= channels else 0
                pp = a + b - c
                pa, pb, pc = abs(pp - a), abs(pp - b), abs(pp - c)
                pr = a if (pa <= pb and pa <= pc) else (b if pb <= pc else c)
                row[x] = (row[x] + pr) & 0xFF
        elif f != 0:
            raise ValueError("bad PNG filter %d" % f)
        out[y * stride:(y + 1) * stride] = row
        prev = row
    # to RGBA
    rgba = bytearray(w * h * 4)
    for y in range(h):
        base = y * stride
        for x in range(w):
            s = base + x * channels
            o = (y * w + x) * 4
            if ct == 6:
                rgba[o:o + 4] = out[s:s + 4]
            elif ct == 2:
                rgba[o:o + 3] = out[s:s + 3]
                rgba[o + 3] = 255
            elif ct == 0:
                g = out[s]
                rgba[o:o + 3] = bytes((g, g, g))
                rgba[o + 3] = 255
            elif ct == 4:
                g, a = out[s], out[s + 1]
                rgba[o:o + 3] = bytes((g, g, g))
                rgba[o + 3] = a
            elif ct == 3:
                idx = out[s] * 3
                rgba[o:o + 3] = plte[idx:idx + 3]
                rgba[o + 3] = 255
    return w, h, rgba

# ------------------------------------------------------- scale / composite

def bbox_alpha(rgba, w, h):
    minx, miny, maxx, maxy = w, h, -1, -1
    for y in range(h):
        row = y * w * 4
        for x in range(w):
            if rgba[row + x * 4 + 3] > 8:
                if x < minx: minx = x
                if x > maxx: maxx = x
                if y < miny: miny = y
                if y > maxy: maxy = y
    if maxx < 0:
        return 0, 0, w - 1, h - 1
    return minx, miny, maxx, maxy


def scale_composite(rgba, w, h, tw, th, fit, bg):
    """Crop to alpha bbox, scale to fit (fit*tw, fit*th) keeping aspect,
    alpha-composite over bg color, return BGR bytes of tw x th."""
    minx, miny, maxx, maxy = bbox_alpha(rgba, w, h)
    cw = maxx - minx + 1
    ch = maxy - miny + 1
    scale = min((tw * fit) / cw, (th * fit) / ch)
    nw = max(1, int(round(cw * scale)))
    nh = max(1, int(round(ch * scale)))
    # integer decimation first (speed), then exact box average
    dec = max(1, int(max(cw / (nw * 2), ch / (nh * 2))))
    dw, dh = cw // dec, ch // dec
    small = bytearray(dw * dh * 4)
    for y in range(dh):
        for x in range(dw):
            # average dec x dec block (sampled at block start; cheap and fine
            # for a logo on flat bg after the final box pass)
            sx = minx + x * dec
            sy = miny + y * dec
            so = (sy * w + sx) * 4
            do = (y * dw + x) * 4
            small[do:do + 4] = rgba[so:so + 4]
    # box average small -> nw x nh
    out = bytearray(nw * nh * 4)
    for y in range(nh):
        y0 = y * dh // nh
        y1 = max(y0 + 1, (y + 1) * dh // nh)
        for x in range(nw):
            x0 = x * dw // nw
            x1 = max(x0 + 1, (x + 1) * dw // nw)
            r = g = b = a = 0
            cnt = 0
            for yy in range(y0, y1):
                for xx in range(x0, x1):
                    so = (yy * dw + xx) * 4
                    r += small[so]; g += small[so + 1]; b += small[so + 2]; a += small[so + 3]
                    cnt += 1
            do = (y * nw + x) * 4
            out[do] = r // cnt; out[do + 1] = g // cnt
            out[do + 2] = b // cnt; out[do + 3] = a // cnt
    # place centered on tw x th bg, emit BGR
    bgr = bytearray(tw * th * 3)
    bgr[0::3] = bytes([bg[2]]) * (tw * th)
    bgr[1::3] = bytes([bg[1]]) * (tw * th)
    bgr[2::3] = bytes([bg[0]]) * (tw * th)
    ox = (tw - nw) // 2
    oy = (th - nh) // 2
    for y in range(nh):
        for x in range(nw):
            so = (y * nw + x) * 4
            alpha = out[so + 3]
            if alpha == 0:
                continue
            sr, sg, sb = out[so], out[so + 1], out[so + 2]
            if alpha == 255:
                r, g, b = sr, sg, sb
            else:
                f = alpha / 255.0
                r = int(sr * f + bg[0] * (1 - f))
                g = int(sg * f + bg[1] * (1 - f))
                b = int(sb * f + bg[2] * (1 - f))
            do = ((oy + y) * tw + (ox + x)) * 3
            bgr[do] = b      # B
            bgr[do + 1] = g  # G
            bgr[do + 2] = r  # R
    return bytes(bgr), nw, nh

# ------------------------------------------------------------------ build

def build_image(args):
    w, h, rgba = decode_png(args.logo)
    bg = bytes.fromhex(args.bg)
    bgr, nw, nh = scale_composite(rgba, w, h, args.width, args.height,
                                  args.fit, bg)
    return bgr, nw, nh


def cmd_build(args):
    data = open(args.input, "rb").read()
    hdr0, images = parse_container(data)
    print("input: %s  size=%d sha256=%s" % (
        args.input, len(data), hashlib.sha256(data).hexdigest()))
    for im in images:
        h = im["header"]
        print("  #%d off=0x%08x %4dx%-4d len=%-8d name=%r" % (
            im["index"], h["off"], h["width"], h["height"], h["length"], h["name"]))

    # pick target image
    target = None
    if args.index is not None:
        target = args.index
    elif args.name:
        rx = re.compile(args.name, re.I)
        for im in images:
            if rx.search(im["header"]["name"]):
                target = im["index"]
                break
    if target is None:
        # default: first full-screen image (the boot screen), else image #0
        for im in images:
            h = im["header"]
            if h["width"] == args.width and h["height"] == args.height:
                target = im["index"]
                break
        else:
            target = 0
    if not (0 <= target < len(images)):
        raise SystemExit("target index %d out of range (0..%d)" % (target, len(images) - 1))
    th = images[target]["header"]
    print("target: #%d name=%r %dx%d" % (target, th["name"], th["width"], th["height"]))

    if args.keep_size:
        ow, oh = th["width"], th["height"]
    else:
        ow, oh = args.width, args.height
    # render logo onto ow x oh canvas
    w, h, rgba = decode_png(args.logo)
    bg = bytes.fromhex(args.bg)
    bgr, nw, nh = scale_composite(rgba, w, h, ow, oh, args.fit, bg)
    payload = rle_encode(bgr)
    print("new image: %dx%d logo %dx%d encoded=%d bytes (raw %d)" % (
        ow, oh, nw, nh, len(payload), ow * oh * BPP))

    # reassemble container
    new_images = []
    for im in images:
        hraw = bytearray(im["header_raw"])
        pay = im["payload"]
        if im["index"] == target:
            struct.pack_into("<2I", hraw, 0x20, ow, oh)          # width, height
            struct.pack_into("<I", hraw, 0x28, len(payload))      # lengthOfData
            pay = payload
        new_images.append((bytes(hraw), pay))

    out = bytearray()
    offsets = [0] * MAX_OFFSETS
    pos = 0
    for i, (hraw, pay) in enumerate(new_images):
        offsets[i] = pos
        out.extend(hraw)
        out.extend(pay)
        pad = block_it(HEADER_SIZE + len(pay)) - (HEADER_SIZE + len(pay))
        out.extend(b"\0" * pad)
        pos = len(out)
    # patch offsets table into header #0
    struct.pack_into("<%dI" % MAX_OFFSETS, out, OFFSET_START, *offsets)

    if len(out) > args.partition_size:
        raise SystemExit("ERROR: built image %d bytes > partition size %d" % (
            len(out), args.partition_size))
    out.extend(b"\0" * (args.partition_size - len(out)))

    with open(args.output, "wb") as f:
        f.write(out)
    print("output: %s size=%d sha256=%s" % (
        args.output, len(out), hashlib.sha256(out).hexdigest()))
    # round-trip verify
    hdr0b, imagesb = parse_container(bytes(out))
    for im in imagesb:
        h = im["header"]
        dec = rle_decode(im["payload"], h["width"] * h["height"] * BPP)
        assert len(dec) == h["width"] * h["height"] * BPP
    print("round-trip verify: %d images, all RLE payloads decode to w*h*3 — OK" % len(imagesb))


def cmd_list(args):
    data = open(args.input, "rb").read()
    hdr0, images = parse_container(data)
    print("file: %s size=%d sha256=%s" % (
        args.input, len(data), hashlib.sha256(data).hexdigest()))
    for im in images:
        h = im["header"]
        print("  #%d off=0x%08x %4dx%-4d len=%-8d special=%d name=%r" % (
            im["index"], h["off"], h["width"], h["height"], h["length"],
            h["special"], h["name"]))


def cmd_verify(args):
    data = open(args.file, "rb").read()
    print("file: %s size=%d sha256=%s" % (
        args.file, len(data), hashlib.sha256(data).hexdigest()))
    if args.partition_size and len(data) > args.partition_size:
        raise SystemExit("FAIL: %d > partition size %d" % (len(data), args.partition_size))
    hdr0, images = parse_container(data)
    print("magic OK (%r), %d images:" % (hdr0["magic"], len(images)))
    for im in images:
        h = im["header"]
        dec = rle_decode(im["payload"], h["width"] * h["height"] * BPP)
        print("  #%d off=0x%08x %4dx%-4d len=%-8d decoded=%d name=%r OK" % (
            im["index"], h["off"], h["width"], h["height"], h["length"],
            len(dec), h["name"]))
    print("VERIFY OK")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("list", help="list images inside a LOGO dump")
    p.add_argument("input")
    p.set_defaults(func=cmd_list)

    p = sub.add_parser("build", help="build a new LOGO image with the Arch logo")
    p.add_argument("--input", required=True, help="original LOGO partition dump (e.g. backups/logo-A.img)")
    p.add_argument("--logo", required=True, help="PNG with the logo (alpha supported)")
    p.add_argument("--output", required=True, help="output image (never overwrites the input)")
    p.add_argument("--index", type=int, default=None, help="image index to replace (default: auto)")
    p.add_argument("--name", default=None, help="regex on image name to pick the target")
    p.add_argument("--bg", default="FFFFFF", help="background RGB hex (default FFFFFF, like the stock boot screen)")
    p.add_argument("--width", type=int, default=1080, help="panel width (default 1080)")
    p.add_argument("--height", type=int, default=1920, help="panel height (default 1920)")
    p.add_argument("--fit", type=float, default=0.8, help="logo size as fraction of the screen (default 0.8)")
    p.add_argument("--keep-size", action="store_true",
                   help="keep the original target image size instead of full screen")
    p.add_argument("--partition-size", type=int, default=16777216,
                   help="LOGO partition size in bytes (default 16777216 = 16 MiB)")
    p.set_defaults(func=cmd_build)

    p = sub.add_parser("verify", help="verify a LOGO image (magic, offsets, RLE, size)")
    p.add_argument("file")
    p.add_argument("--partition-size", type=int, default=16777216)
    p.set_defaults(func=cmd_verify)

    args = ap.parse_args()
    if getattr(args, "cmd", None) == "build":
        if args.input == args.output:
            raise SystemExit("refusing to overwrite the input file")
    args.func(args)


if __name__ == "__main__":
    main()
