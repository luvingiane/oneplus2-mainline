#!/usr/bin/env bash
# Pack a boot image for `fastboot boot` (RAM only) on the OnePlus 2:
#   Image.gz + the four board-revision DTBs appended (the bootloader picks the
#   one whose qcom,board-id matches) + our initramfs.
# Addresses: CAF LK for msm8994 ignores the header (ABOOT_IGNORE_BOOT_HEADER_ADDRS)
# and loads a 64-bit kernel at 0x80000, the DTB at 0x02500000, the ramdisk at
# 0x02700000; the header carries the same values, so a bootloader that does
# honour it ends up identical. Pagesize 4096 as LineageOS's BoardConfig.mk.
#
#   scripts/build-boot.sh <name> [--cmdline "..."]
# Output: out/<name>.img + out/<name>.sha256
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
B=$ROOT/build
# KSRC / DTB_OUT: another kernel tree (e.g. build/linux-6.12-op2, build/dtbs-612)
SRC=${KSRC:-$B/linux-7.3}
DTBS=${DTB_OUT:-$B/dtbs}
NAME=${1:?image name}; shift
EXTRA=
while [ $# -gt 0 ]; do
	case "$1" in
	--cmdline) EXTRA=$2; shift ;;
	*) echo "unknown option $1" >&2; exit 2 ;;
	esac
	shift
done
CMDLINE="console=tty0 loglevel=7 clk_ignore_unused pd_ignore_unused regulator_ignore_unused panic=10 reboot=warm op2.deadman=900 $EXTRA"

[ -x "$B/busybox-arm64" ] || bash "$ROOT/scripts/build-busybox.sh"
"$B/toolchain/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-gcc" \
	-static -Os -s -Wall -o "$B/op2-kick" "$ROOT/tools/op2-kick/op2-kick.c"
"$B/toolchain/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-gcc" \
	-static -Os -s -Wall -o "$B/op2-touchled" "$ROOT/tools/op2-touchled/op2-touchled.c"
"$B/toolchain/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-gcc" \
	-static -Os -s -Wall -o "$B/op2-dcs" "$ROOT/tools/op2-dcs/op2-dcs.c"
"$B/toolchain/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-gcc" \
	-static -Os -s -Wall -o "$B/op2-keyled" "$ROOT/tools/op2-keyled/op2-keyled.c"
mkdir -p "$ROOT/out" "$B/initramfs"

# test patterns for the display check (24 and 32 bpp), gzip'd
python3 -I - "$B/initramfs" <<'EOF'
import gzip, sys
W, H, out = 1080, 1920, sys.argv[1]
def px(x, y):
    if x < 8 or y < 8 or x >= W - 8 or y >= H - 8:
        return (255, 255, 255)
    return [(255, 0, 0), (0, 255, 0), (0, 0, 255)][min(y * 3 // H, 2)]
rows = {}
for bpp in (24, 32):
    data = bytearray()
    for y in range(H):
        band = 'b' if (y < 8 or y >= H - 8) else min(y * 3 // H, 2)
        key = (bpp, band)
        if key not in rows:
            r = bytearray()
            for x in range(W):
                R, G, B = px(x, y)
                # r8g8b8 in memory is B, G, R; xrgb8888 is B, G, R, X
                r += bytes((B, G, R)) if bpp == 24 else bytes((B, G, R, 0))
            rows[key] = bytes(r)
        data += rows[key]
    with gzip.open(f"{out}/pattern{bpp}.raw.gz", "wb", 9) as f:
        f.write(data)
EOF

printf 'root:x:0:0:root:/root:/bin/sh\n' > "$B/initramfs/passwd"
printf 'root:x:0:\n' > "$B/initramfs/group"
printf '/bin/sh\n' > "$B/initramfs/shells"
[ -x "$B/dropbearmulti" ] || bash "$ROOT/scripts/build-dropbear.sh"
LIST=$B/initramfs.list
cat > "$LIST" <<EOF
dir /bin 0755 0 0
dir /dev 0755 0 0
dir /proc 0755 0 0
dir /sys 0755 0 0
dir /run 0755 0 0
dir /tmp 1777 0 0
dir /etc 0755 0 0
nod /dev/console 0600 0 0 c 5 1
nod /dev/null 0666 0 0 c 1 3
nod /dev/kmsg 0600 0 0 c 1 11
file /bin/busybox $B/busybox-arm64 0755 0 0
slink /bin/sh busybox 0777 0 0
file /init $ROOT/initramfs/init 0755 0 0
file /bin/op2-kick $B/op2-kick 0755 0 0
file /bin/op2-touchled $B/op2-touchled 0755 0 0
file /bin/op2-keyled $B/op2-keyled 0755 0 0
file /bin/op2-dcs $B/op2-dcs 0755 0 0
file /etc/jd35695-on.seq $ROOT/research/jd35695-on.seq 0644 0 0
file /bin/dropbearmulti $B/dropbearmulti 0755 0 0
slink /bin/dropbear dropbearmulti 0777 0 0
slink /bin/dropbearkey dropbearmulti 0777 0 0
dir /etc/dropbear 0700 0 0
file /etc/passwd $B/initramfs/passwd 0644 0 0
file /etc/group $B/initramfs/group 0644 0 0
file /etc/shells $B/initramfs/shells 0644 0 0
dir /root 0700 0 0
dir /root/.ssh 0700 0 0
file /root/.ssh/authorized_keys $ROOT/keys/op2_ed25519.pub 0600 0 0
file /pattern24.raw.gz $B/initramfs/pattern24.raw.gz 0644 0 0
file /pattern32.raw.gz $B/initramfs/pattern32.raw.gz 0644 0 0
EOF
# GPU firmware inside the image. FW=0 builds a "collector" image without it:
# the adreno probe then fails before hw_init, the phone stays up, and the
# serial console / pstore of previous GPU-panic boots can be read.
if [ "${FW:-1}" = 1 ]; then cat >> "$LIST" <<EOF
dir /lib 0755 0 0
dir /lib/firmware 0755 0 0
dir /lib/firmware/qcom 0755 0 0
file /lib/firmware/qcom/a420_pfp.fw $ROOT/firmware/qcom/a420_pfp.fw 0644 0 0
file /lib/firmware/qcom/a420_pm4.fw $ROOT/firmware/qcom/a420_pm4.fw 0644 0 0
EOF
fi
[ -x "$SRC/usr/gen_init_cpio" ] || make -C "$SRC" ARCH=arm64 usr/gen_init_cpio >/dev/null
"$SRC/usr/gen_init_cpio" "$LIST" | gzip -9 > "$B/initramfs.cpio.gz"

# the decompressed kernel (with BSS) must end below the DTB: this LK puts it
# at 0x01e00000 (proven 2026-10-25: a kernel ending at 0x1ed0000 never ran)
isz=$(python3 -c "import struct,sys;print(struct.unpack_from('<Q',open(sys.argv[1],'rb').read(24),16)[0])" "$SRC/arch/arm64/boot/Image")
[ $((0x80000 + isz)) -lt $((0x01e00000)) ] || { echo "kernel image_size $isz overlaps the DTB at 0x01e00000"; exit 1; }
echo "kernel image_size $((isz / 1048576)) MiB: ends at $(printf 0x%x $((0x80000 + isz))), DTB at 0x1e00000"
cat "$SRC/arch/arm64/boot/Image.gz" "$DTBS"/msm8994-oneplus-oneplus2-v*-hw*.dtb > "$B/Image.gz-dtb"
echo "appended DTBs: $(ls "$DTBS"/msm8994-oneplus-oneplus2-v*-hw*.dtb | wc -l)"
mkbootimg --kernel "$B/Image.gz-dtb" --ramdisk "$B/initramfs.cpio.gz" \
	--base 0x00000000 --pagesize 4096 --kernel_offset 0x00080000 \
	--ramdisk_offset 0x02700000 --tags_offset 0x02500000 \
	--cmdline "$CMDLINE" -o "$ROOT/out/$NAME.img"
(cd "$ROOT/out" && sha256sum "$NAME.img" > "$NAME.sha256")
size=$(stat -c %s "$ROOT/out/$NAME.img")
[ "$size" -lt 67108864 ] || { echo "image bigger than the 64 MiB boot partition"; exit 1; }
echo "out/$NAME.img  $size bytes  kernel $(cat "$SRC/include/config/kernel.release")"
echo "cmdline: $CMDLINE"
