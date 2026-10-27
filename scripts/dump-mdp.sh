#!/usr/bin/env bash
# Dump the MDP5 blocks (msm8994 offsets from mdp5_cfg.c, MDP base 0xfd901000)
# of the running phone into the given file, "addr value" per line.
#   scripts/dump-mdp.sh <out-file>
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
B=$ROOT/build
out=${1:?file}
"$B/toolchain/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu/bin/aarch64-none-linux-gnu-gcc" \
	-static -Os -s -Wall -o "$B/op2-peek" "$ROOT/tools/op2-peek/op2-peek.c"
"$ROOT/scripts/op2-ssh" 'cat > /tmp/op2-peek && chmod +x /tmp/op2-peek' < "$B/op2-peek"
# MDSS top, MDP top, CTL0-4, VIG0, RGB0, DMA0, LM0-2, DSPP0-2, INTF0-2, PP0-2
"$ROOT/scripts/op2-ssh" /tmp/op2-peek \
	0xfd900000 0x100  0xfd901000 0x400  0xfd902000 0xa00 \
	0xfd905000 0x300  0xfd915000 0x300  0xfd925000 0x300 \
	0xfd945000 0x3000 \
	0xfd955000 0x100  0xfd957000 0x100  0xfd959000 0x100 \
	0xfd96b000 0x1300 0xfd971000 0x1100 > "$out"
wc -l < "$out"
