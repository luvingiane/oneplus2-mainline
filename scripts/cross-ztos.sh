#!/usr/bin/env bash
# Cross-compile ztOS (ztmetro + apps) on the PC for the OnePlus 2 (aarch64), against a copy of the phone's /usr
# (build/sysroot-b: tar of usr/include, usr/lib, usr/share/{pkgconfig,wayland*} from B).
#   scripts/cross-ztos.sh <ztOS-checkout>/ztmetro [make targets...]      (default target: ztmetro)
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC=${1:?path to the ztmetro dir}; shift
SR=$ROOT/build/sysroot-b
TC=$ROOT/build/toolchain/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu/bin
export PKG_CONFIG_SYSROOT_DIR=$SR
export PKG_CONFIG_LIBDIR=$SR/usr/lib/pkgconfig:$SR/usr/share/pkgconfig
export PATH=$TC:$PATH
cd "$SRC"
# FOREIGN= : the Makefile deletes executables that are not for this (x86) machine; ours are aarch64 on purpose
exec make -j"${JOBS:-4}" FOREIGN= CC="aarch64-none-linux-gnu-gcc --sysroot=$SR" "${@:-ztmetro}"
