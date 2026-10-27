#!/usr/bin/env bash
# Read every eMMC partition off the phone into backup/<label>/, with a SHA-256
# manifest, and check each image against a hash computed on the phone itself.
# Read-only on the phone (dd if=<partition> only). Needs a root adb shell:
# a recovery (adb state "recovery") or Android with su.
# Big partitions (system, userdata, cache) are skipped unless --all.
# Usage: scripts/backup-partitions.sh <label> [--all]
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
label=${1:?label, e.g. A-broken or B-target}
all=${2:-}
out="$here/backup/$label"
mkdir -p "$out"

state=$(adb get-state 2>/dev/null)
if [ "$state" = recovery ]; then
	pre=""
elif [ "$state" = device ] && adb shell su -c id 2>/dev/null | grep -q 'uid=0'; then
	pre="su -c"
else
	echo "need a root adb shell (recovery, or Android with su); state='$state'"; exit 1
fi
# wrap a remote command so it runs as root
rc() { if [ -n "$pre" ]; then printf 'su -c "%s"' "$*"; else printf '%s' "$*"; fi; }
shellroot() { adb shell "$(rc "$*")" | tr -d '\r'; }

dir=/dev/block/bootdevice/by-name
shellroot "ls -1 $dir" >/dev/null 2>&1 || dir=$(adb shell 'ls -d /dev/block/platform/*/by-name' | tr -d '\r' | head -1)
names=$(shellroot "ls -1 $dir")
[ -n "$names" ] || { echo "no partition list from the phone"; exit 1; }
echo "$names" > "$out/partition-list.txt"
shellroot "ls -l $dir" > "$out/by-name.txt"

devhash=$(shellroot 'command -v sha256sum >/dev/null && echo sha256sum || echo md5sum')
echo "phone-side hash: $devhash"
critical="modem persist modemst1 modemst2 fsg fsc sec boot recovery aboot sbl1 tz rpm hyp pmic DDR misc config oem_stanvbk LOGO"

: > "$out/SHA256SUMS.new"
fail=0
for p in $names; do
	case "$p" in
	system|userdata|cache) [ "$all" = --all ] || { echo "skip $p (big; use --all)"; continue; } ;;
	esac
	img="$out/$p.img"
	printf '%-16s ' "$p"
	adb exec-out "$(rc "dd if=$dir/$p bs=1048576 2>/dev/null")" > "$img"
	adb get-state >/dev/null 2>&1 || { echo "adb lost during $p: stopping"; exit 1; }
	want=$(shellroot "$devhash $dir/$p" | awk '{print $1}')
	if [ "$devhash" = sha256sum ]; then got=$(sha256sum "$img" | awk '{print $1}')
	else got=$(md5sum "$img" | awk '{print $1}'); fi
	if [ -n "$want" ] && [ "$want" = "$got" ]; then
		echo "ok  $(stat -c %s "$img") bytes"
	else
		echo "MISMATCH phone=$want host=$got"; fail=1
	fi
	(cd "$out" && sha256sum "$p.img") >> "$out/SHA256SUMS.new"
done
mv "$out/SHA256SUMS.new" "$out/SHA256SUMS"
for c in $critical; do echo "$names" | grep -qx "$c" || echo "note: no partition named $c"; done
[ $fail = 0 ] && echo "all images match the phone" || echo "SOME IMAGES DO NOT MATCH — do not touch the phone"
exit $fail
