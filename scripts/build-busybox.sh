#!/usr/bin/env bash
# Static aarch64 busybox for the test initramfs (same Arm GNU toolchain as ztOS).
# Output: build/busybox-arm64
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC=$ROOT/build/busybox-1.37.0
TC=$ROOT/build/toolchain/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu/bin
export PATH=$TC:$PATH LC_ALL=C
cd "$SRC"
make defconfig >/dev/null
sed -i -e 's/^# CONFIG_STATIC is not set/CONFIG_STATIC=y/' \
	-e 's/^CONFIG_TC=y/# CONFIG_TC is not set/' \
	-e 's/^CONFIG_FEATURE_TC_INGRESS=y/# CONFIG_FEATURE_TC_INGRESS is not set/' \
	-e 's/^CONFIG_SHA1_HWACCEL=y/# CONFIG_SHA1_HWACCEL is not set/' \
	-e 's/^CONFIG_SHA256_HWACCEL=y/# CONFIG_SHA256_HWACCEL is not set/' .config
{ yes '' || :; } | make oldconfig >/dev/null
make -j"$(nproc)" CROSS_COMPILE=aarch64-none-linux-gnu- busybox >/dev/null 2>&1 || { echo "busybox build failed"; exit 1; }
cp busybox "$ROOT/build/busybox-arm64"
file "$ROOT/build/busybox-arm64"
