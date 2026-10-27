#!/usr/bin/env bash
# RAM-boot a test image (`fastboot boot`, nothing is flashed) and collect the
# result over the USB network. The phone must already be in fastboot mode.
#   scripts/test-boot.sh out/<name>.img
# Writes logs/boot-<name>-<time>/ (op2boot.log, dmesg, pstore, interfaces).
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
IMG=${1:?image}
name=$(basename "$IMG" .img)
out=$ROOT/logs/boot-$name-$(date +%Y%m%d-%H%M%S)
mkdir -p "$out"
timeout 5 fastboot devices | grep -q "^${OP2_SERIAL:?set OP2_SERIAL to your phone's fastboot serial}" || { echo "no phone in fastboot mode"; exit 1; }
(cd "$(dirname "$IMG")" && sha256sum -c "$name.sha256") || exit 1
echo "fastboot -s "${OP2_SERIAL:?set OP2_SERIAL to your phone's fastboot serial}" boot $IMG (RAM only)"
fastboot -s "${OP2_SERIAL:?set OP2_SERIAL to your phone's fastboot serial}" boot "$IMG" 2>&1 | tee "$out/fastboot.txt"
echo "waiting up to 120 s for 172.16.42.1 ..."
for i in $(seq 1 120); do
	ping -c1 -W1 172.16.42.1 >/dev/null 2>&1 && break
	sleep 1
done
lsusb > "$out/lsusb.txt"
ip -br addr > "$out/host-ip.txt"
if ! ping -c1 -W1 172.16.42.1 >/dev/null 2>&1; then
	echo "NO NETWORK from the phone. USB: $(lsusb | grep -iE '18d1|2a70|05c6' || echo none)"
	echo "the deadman/watchdog will return it to its normal boot; pstore will hold the log"
	exit 2
fi
P="python3 $ROOT/scripts/psh.py"
$P 'cat /run/op2boot.log' > "$out/op2boot.log"
$P -t 60 'dmesg' > "$out/dmesg.txt"
$P 'for f in /sys/fs/pstore/*; do echo "== $f"; cat $f; done' > "$out/pstore.txt"
$P 'cat /proc/interrupts; ls -l /dev/fb* /dev/dri /dev/input /dev/watchdog*; cat /proc/bus/input/devices' > "$out/devices.txt"
cat "$out/op2boot.log"
echo "logs: $out"
