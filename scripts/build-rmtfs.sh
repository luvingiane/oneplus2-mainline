#!/usr/bin/env bash
# Static aarch64 rmtfs (Qualcomm remote file system service: the modem asks the AP for its EFS/NV partitions).
# Sources from github.com/linux-msm/rmtfs and /qrtr (cloned into build/rmtfs, not part of this repo);
# libudev is replaced by tools/rmtfs-udev-stub (only the sysfs reads rmtfs needs), so it runs on the bare initramfs.
#   scripts/build-rmtfs.sh   ->  build/rmtfs/rmtfs-static
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
D=$ROOT/build/rmtfs; mkdir -p "$D"; cd "$D"
for r in rmtfs qrtr; do [ -d $r ] || git clone -q --depth 1 https://github.com/linux-msm/$r.git; done
# OnePlus 2 modem asks for /oem/oem_stanvbk and /oem/oem_dycnvbk (upstream only knows /oem/nvbk/*)
[ -d rmtfs ] && (cd rmtfs && grep -q "/oem/oem_stanvbk" storage.c || git apply "$ROOT/tools/rmtfs-udev-stub/rmtfs-oem-paths.patch")
export PATH=$ROOT/build/toolchain/arm-gnu-toolchain-14.2.rel1-x86_64-aarch64-none-linux-gnu/bin:$PATH
aarch64-none-linux-gnu-gcc -static -O2 -I"$ROOT/tools/rmtfs-udev-stub" -Iqrtr/include -Iqrtr/lib -Iqrtr/src \
  -o rmtfs-static rmtfs/*.c qrtr/lib/*.c "$ROOT/tools/rmtfs-udev-stub/libudev.c" -lpthread
file rmtfs-static
