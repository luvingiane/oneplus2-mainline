#!/bin/bash
# Map the OnePlus 2 stock firmware (extracted from eMMC p42 system/etc + p2 bt +
# p37 persist, see REPORT-FIRMWARE.md) to the paths mainline 7.3 drivers request
# (verified in build/linux-7.3, research/verifica-2026-11-02-mainline73.md).
# Usage: scripts/fw-map.sh <extracted-dir> <dest-rootfs-firmware-dir>
#   e.g. scripts/fw-map.sh firmware/extracted-B /path/to/rootfs/lib/firmware
set -euo pipefail
SRC=${1:?extracted dir}; DST=${2:?dest /lib/firmware}
mkdir -p "$DST/qca" "$DST/ath10k/QCA6174/hw3.0"

# --- BT QCA6174: hci_qca "qcom,qca6174-bt" + DT firmware-name (btqca.c:784,870) ---
# stock names load 1:1 as qca/<name>
for f in nvm_tlv_3.2.bin rampatch_tlv_3.2.tlv; do
	src=$(find "$SRC" -name "$f" | head -1)
	[ -n "$src" ] && cp "$src" "$DST/qca/$f" && echo "qca/$f <- $src"
done

# --- Wi-Fi QCA6174 ath10k PCI hw3.0: ath10k/QCA6174/hw3.0/firmware-N.bin (N=6..2,
#     hw.h:127-129) + board-2.bin (core.c:1679) ---
# firmware-5.bin is NOT on the eMMC (CAF wcnss loads only the nv.bin,
# lineage wcnss_wlan.c:265) -> must come from linux-firmware; only the board
# data (nv/calibration) is on the phone:
nv=$(find "$SRC" -name 'WCNSS_qcom_wlan_nv.bin' | head -1)
[ -n "$nv" ] && echo "TODO wrap nv -> board-2.bin: $nv (ath10k board-data container)"
mac=$(find "$SRC" -name 'wlan_mac.bin' | head -1)
[ -n "$mac" ] && cp "$mac" "$DST/wlan_mac.bin" && echo "wlan_mac.bin <- $mac"

echo "NOTE: place ath10k/QCA6174/hw3.0/firmware-5.bin from linux-firmware manually."
