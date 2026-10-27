#!/usr/bin/env bash
# Copy the user's media (internal storage) off the phone, then compare the
# file count and total size on both sides. Read-only on the phone.
# Usage: scripts/pull-media.sh <label>
set -u
here=$(cd "$(dirname "$0")/.." && pwd)
label=${1:?label}
out="$here/backup/$label/media"
mkdir -p "$out"
src=/sdcard
adb shell "ls /data/media/0" >/dev/null 2>&1 && [ "$(adb get-state)" = recovery ] && src=/data/media/0
echo "pulling $src -> $out"
adb pull -a "$src/." "$out/" 2>&1 | tail -3
pn=$(adb shell "find $src/ -type f | wc -l" | tr -d '\r')
pb=$(adb shell "du -sk $src/" | awk '{print $1}')
hn=$(find "$out" -type f | wc -l)
hb=$(du -sk "$out" | awk '{print $1}')
echo "phone: $pn files, ${pb} KiB   host: $hn files, ${hb} KiB"
(cd "$out" && find . -type f -print0 | sort -z | xargs -0 sha256sum) > "$here/backup/$label/media-SHA256SUMS"
[ "$pn" = "$hn" ] && echo "file count matches" || echo "FILE COUNT DIFFERS"
