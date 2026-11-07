#!/usr/bin/env bash
# Static aarch64 build of tools/op2-sensord/op2-sensord.c (needs the qrtr sources cloned by scripts/build-rmtfs.sh into build/rmtfs/qrtr)
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
Q=$ROOT/build/rmtfs/qrtr
[ -d "$Q" ] || { mkdir -p "$ROOT/build/rmtfs"; git clone -q --depth 1 https://github.com/linux-msm/qrtr.git "$Q"; }
export PATH=$ROOT/build/toolchain/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu/bin:$PATH
aarch64-none-linux-gnu-gcc -static -O2 -Wall -I"$Q/include" -I"$Q/lib" -o "$ROOT/build/op2-sensord" "$ROOT/tools/op2-sensord/op2-sensord.c" "$Q"/lib/*.c -lm
file "$ROOT/build/op2-sensord"
