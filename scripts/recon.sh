#!/usr/bin/env bash
# Phase 0 recon. Read-only: never writes to the phone.
# Works with the phone in Android (adb), recovery (adb) or fastboot.
# Usage: scripts/recon.sh [label]      (label: e.g. "A-broken" or "B-target")
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
label=${1:-phone}
out="$here/logs/recon-$label-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$out"
echo "recon -> $out"

run() { # run <file> <cmd...>
	local f=$1; shift
	{ echo "\$ $*"; timeout 60 "$@" 2>&1; echo "[exit $?]"; } > "$out/$f"
}

lsusb > "$out/lsusb.txt"
adb devices -l > "$out/adb-devices.txt" 2>&1
timeout 5 fastboot devices -l > "$out/fastboot-devices.txt" 2>&1

if timeout 5 fastboot devices | grep -q .; then
	echo "mode: fastboot"
	run fastboot-getvar-all.txt fastboot getvar all
	run fastboot-oem-device-info.txt fastboot oem device-info
	exit 0
fi

state=$(adb get-state 2>/dev/null)
echo "adb state: ${state:-none}"
case "$state" in
device|recovery) ;;
*) echo "no usable adb/fastboot connection (state: '$state')"; exit 1 ;;
esac

run getprop.txt adb shell getprop
run uname.txt adb shell uname -a
run id.txt adb shell id
run su-id.txt adb shell su -c id
run cpuinfo.txt adb shell cat /proc/cpuinfo
run meminfo.txt adb shell cat /proc/meminfo
run cmdline.txt adb shell cat /proc/cmdline
run partitions.txt adb shell cat /proc/partitions
run by-name.txt adb shell 'ls -l /dev/block/bootdevice/by-name/ 2>/dev/null || ls -l /dev/block/platform/*/by-name/'
run mounts.txt adb shell cat /proc/mounts
run df.txt adb shell df
run lsmod.txt adb shell 'lsmod 2>/dev/null || cat /proc/modules'
run dmesg.txt adb shell 'dmesg 2>/dev/null || su -c dmesg'
run dt-model.txt adb shell 'cat /proc/device-tree/model; echo; od -An -tx4 /proc/device-tree/qcom,msm-id; od -An -tx4 /proc/device-tree/qcom,board-id'
run sys-class.txt adb shell 'for c in /sys/class/*; do echo "== $c"; ls $c; done'
run i2c-devices.txt adb shell 'for d in /sys/bus/i2c/devices/*; do echo "$d $(cat $d/name 2>/dev/null)"; done'
run input.txt adb shell 'cat /proc/bus/input/devices'
run fb.txt adb shell 'cat /sys/class/graphics/fb0/modes /sys/class/graphics/fb0/msm_fb_panel_info 2>/dev/null'
run pci.txt adb shell 'for d in /sys/bus/pci/devices/*; do echo "$d $(cat $d/vendor) $(cat $d/device)"; done'
run asound.txt adb shell 'cat /proc/asound/cards /proc/asound/pcm 2>/dev/null'
run firmware-dirs.txt adb shell 'ls -lR /firmware /system/etc/firmware /vendor/firmware /persist 2>/dev/null; su -c "ls -lR /persist" 2>/dev/null'
run storage.txt adb shell 'ls -la /sdcard/ /data/media/0/ 2>/dev/null; du -sh /sdcard/* 2>/dev/null'
run crypto.txt adb shell 'getprop ro.crypto.state; getprop ro.crypto.type'
echo "done: $(ls "$out" | wc -l) files"
