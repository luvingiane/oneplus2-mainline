#!/usr/bin/env bash
# build-modem-diag.sh — cross-compila tools/modem-diag/diag.c in un binario
# statico aarch64, pronto da copiare su A (che non ha udev né python).
#
# Uso: scripts/build-modem-diag.sh [output]
#   output  default: out/modem-diag
#
# Toolchain: prima quella del repo (build/toolchain/arm-gnu-toolchain-*),
# poi il fallback aarch64-none-linux-gnu-gcc di sistema (se presente).
# La compilazione e' solo di verifica: il binario NON va eseguito qui,
# la prova su A la fa il proprietario.
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC="$ROOT/tools/modem-diag/diag.c"
OUT=${1:-"$ROOT/out/modem-diag"}

TC="$ROOT/build/toolchain/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu"
CC="$TC/bin/aarch64-none-linux-gnu-gcc"
if [ ! -x "$CC" ]; then
	CC=$(command -v aarch64-none-linux-gnu-gcc || command -v aarch64-linux-gnu-gcc)
fi

# -Wno-format-truncation: i path sysfs sono corti, snprintf tronca in modo sicuro
CFLAGS="-static -O2 -Wall -Wextra -Wno-format-truncation"

mkdir -p "$(dirname "$OUT")"
"$CC" $CFLAGS -o "$OUT" "$SRC"
"$CC" $CFLAGS -s -o "$OUT.stripped" "$SRC" 2>/dev/null || true
ls -la "$OUT"
echo "OK: $OUT (ELF64 AArch64 statico; copialo su A e lancialo lì, es.: ./diag -t 120 -v)"
