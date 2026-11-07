#!/usr/bin/env bash
# Cross-compile Slipmat (slipmat, slipmatd, climat; Rust, GTK4/libadwaita) for the OnePlus 2 (aarch64) on the PC.
#   scripts/build-slipmat.sh            (sources: build/slipmat/Slipmat-0.12.0, sysroot copied from B: build/slipmat/sysroot-slip,
#                                        Rust std for aarch64 in build/slipmat/rsroot) -> build/slipmat/Slipmat-0.12.0/target/aarch64-unknown-linux-gnu/release
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SL=$ROOT/build/slipmat; SR=$SL/sysroot-slip
export PATH=$SL/rust/bin:$ROOT/build/toolchain/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu/bin:$PATH
export PKG_CONFIG_ALLOW_CROSS=1 PKG_CONFIG_SYSROOT_DIR=$SR
export PKG_CONFIG_LIBDIR=$SR/usr/lib/pkgconfig:$SR/usr/share/pkgconfig
export CARGO_BUILD_TARGET=aarch64-unknown-linux-gnu
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_LINKER=aarch64-none-linux-gnu-gcc
export CARGO_TARGET_AARCH64_UNKNOWN_LINUX_GNU_RUSTFLAGS="-C link-arg=--sysroot=$SR"
export CC_aarch64_unknown_linux_gnu="aarch64-none-linux-gnu-gcc --sysroot=$SR"
export CARGO_PROFILE_RELEASE_DEBUG=0
cd "$SL/Slipmat-0.12.0"
exec cargo build --release --locked "$@"
