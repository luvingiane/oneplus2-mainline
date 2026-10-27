#!/usr/bin/env bash
# Static aarch64 dropbear (sshd + key generator) for the test initramfs.
# Source: matt.ucc.asn.au, GPG-verified (Dropbear release key F29C6773).
# Output: build/dropbearmulti
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
V=2026.94
TC=$ROOT/build/toolchain/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu/bin
export PATH=$TC:$PATH
cd "$ROOT/build"
[ -d "dropbear-$V" ] || tar xf "dropbear-dl/dropbear-$V.tar.bz2"
cd "dropbear-$V"
[ -f Makefile ] || ./configure --host=aarch64-none-linux-gnu --disable-zlib --enable-static \
	--disable-lastlog --disable-utmp --disable-utmpx --disable-wtmp --disable-wtmpx \
	--disable-pututline --disable-pututxline >/dev/null
# key-only login: no password auth (also: static glibc has no crypt())
printf '#define DROPBEAR_SVR_PASSWORD_AUTH 0\n#define DROPBEAR_CLI_PASSWORD_AUTH 0\n' > localoptions.h
make -j"$(nproc)" PROGRAMS="dropbear dropbearkey" MULTI=1 STATIC=1 >/dev/null 2>&1 ||
	{ make PROGRAMS="dropbear dropbearkey" MULTI=1 STATIC=1 2>&1 | tail -20; exit 1; }
aarch64-none-linux-gnu-strip dropbearmulti
cp dropbearmulti "$ROOT/build/dropbearmulti"
file "$ROOT/build/dropbearmulti"
