#!/usr/bin/env bash
# Static aarch64 build of tools/qmux/qmux.c  ->  build/qmux
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
export PATH=$ROOT/build/toolchain/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu/bin:$PATH
aarch64-none-linux-gnu-gcc -static -O2 -Wall -o "$ROOT/build/qmux" "$ROOT/tools/qmux/qmux.c"
file "$ROOT/build/qmux"
