#!/usr/bin/env bash
# One unattended test cycle (RAM only, nothing flashed):
#   fastboot -s "${OP2_SERIAL:?set OP2_SERIAL to your phone's fastboot serial}" boot <img> -> if the USB network comes up, collect logs over it;
#   otherwise wait for the phone to come back to fastboot (the init sets the
#   IMEM restart reason to fastboot first thing, so a watchdog/panic reset
#   lands there), RAM-boot TWRP and pull /sys/fs/pstore (our ramoops uses
#   the OnePlus layout, which TWRP's kernel keeps); end in fastboot.
#   scripts/cycle.sh out/<name>.img [max-wait-seconds]
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
IMG=$1; WAIT=${2:-600}
TWRP=$ROOT/build/twrp/twrp-3.2.1-0-oneplus2.img
name=$(basename "$IMG" .img)
out=$ROOT/logs/cycle-$name-$(date +%Y%m%d-%H%M%S); mkdir -p "$out"
say() { echo "$(date +%T) $*" | tee -a "$out/cycle.txt"; }
to_fastboot() {
	for i in $(seq 1 100); do
		timeout 2 fastboot devices | grep -q "^${OP2_SERIAL:?set OP2_SERIAL to your phone's fastboot serial}" && return 0
		adb -s "${OP2_SERIAL:?set OP2_SERIAL to your phone's fastboot serial}" get-state 2>/dev/null | grep -qE 'recovery|device' && adb -s "${OP2_SERIAL:?set OP2_SERIAL to your phone's fastboot serial}" reboot bootloader >/dev/null 2>&1
		sleep 3
	done; return 1
}
to_fastboot || { say "phone not in fastboot"; exit 1; }
say "boot $name"; fastboot -s "${OP2_SERIAL:?set OP2_SERIAL to your phone's fastboot serial}" boot "$IMG" >> "$out/cycle.txt" 2>&1
sleep 8
for i in $(seq 1 40); do ping -c1 -W1 172.16.42.1 >/dev/null 2>&1 && break; sleep 2; done
if ping -c1 -W1 172.16.42.1 >/dev/null 2>&1; then
	say "USB network UP"
	P="python3 $ROOT/scripts/psh.py"
	$P 'cat /run/op2boot.log' > "$out/op2boot.log"; $P -t 60 dmesg > "$out/dmesg.txt"
	$P 'ls /sys/class/udc; cat /proc/bus/input/devices; ls -l /dev/fb* /dev/dri /dev/watchdog*' > "$out/devices.txt"
	$P 'devmem 0xfe87f65c 32 0x77665500; reboot -f' >/dev/null 2>&1
	cat "$out/op2boot.log"
else
	say "no USB network; waiting up to $WAIT s for the phone to come back"
	for i in $(seq 1 $((WAIT / 3))); do
		s=$(lsusb | grep -iE '2a70|18d1|05c6' | sed 's/Bus [0-9]* Device [0-9]*: //')
		[ -n "$s" ] && { say "back on USB after ~$((i * 3 + 90)) s: $s"; break; }
		sleep 3
	done
fi
to_fastboot || { say "did not come back to fastboot (needs the power key)"; exit 2; }
if [ ! -s "$out/op2boot.log" ]; then
	say "fastboot; RAM-boot TWRP to read pstore"
	fastboot -s "${OP2_SERIAL:?set OP2_SERIAL to your phone's fastboot serial}" boot "$TWRP" >> "$out/cycle.txt" 2>&1
	for i in $(seq 1 60); do adb -s "${OP2_SERIAL:?set OP2_SERIAL to your phone's fastboot serial}" get-state 2>/dev/null | grep -q recovery && break; sleep 2; done
	adb shell 'mkdir -p /tmp/ps; mount -t pstore pstore /tmp/ps 2>/dev/null; ls -la /tmp/ps' 2>/dev/null | grep -v tzdata | tee -a "$out/cycle.txt"
	for f in $(adb shell 'ls /tmp/ps' 2>/dev/null | grep -v tzdata | tr -d '\r'); do
		adb shell "cat /tmp/ps/$f" 2>/dev/null | grep -v tzdata > "$out/pstore-$f"
	done
	adb shell 'dmesg | grep -iE "ramoops|pstore|Power-on reason|Power-off reason"' 2>/dev/null | grep -v tzdata >> "$out/cycle.txt"
	adb -s "${OP2_SERIAL:?set OP2_SERIAL to your phone's fastboot serial}" reboot bootloader >/dev/null 2>&1; to_fastboot
fi
say "done: $out"; ls -l "$out"
