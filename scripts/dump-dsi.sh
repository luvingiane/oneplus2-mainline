#!/usr/bin/env bash
# Dump DSI0 controller (0xfd998000, 0x260), PLL (0xfd998300, 0x200), PHY
# (0xfd998500, 0x280) and PHY regulator (0xfd998780, 0x30) registers from
# the running phone into the given file (one "addr value" per line).
set -u
out=${1:?file}
python3 "$(dirname "$0")/psh.py" -t 120 'd() { a=$1; e=$2; while [ $a -lt $e ]; do echo "$(printf 0x%x $a) $(devmem $(printf 0x%x $a) 32)"; a=$((a+4)); done; }; d $((0xfd998000)) $((0xfd998260)); d $((0xfd998300)) $((0xfd998500)); d $((0xfd998500)) $((0xfd9987b0))' 2>&1 | grep -E '^0x' > "$out"
wc -l < "$out"
