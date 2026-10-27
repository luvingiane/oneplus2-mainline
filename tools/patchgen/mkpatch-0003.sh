#!/usr/bin/env bash
# Regenerate kernel/patches/0003 from a tree where it is not applied yet.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
SRC=$ROOT/build/linux-7.3
S=$(mktemp -d)
D=drivers/gpu/drm/msm/dsi
FILES="phy/dsi_phy_20nm.c phy/dsi_phy.c phy/dsi_phy.h dsi.h dsi_manager.c"
cd "$SRC"
mkdir -p "$S/a/$D/phy" "$S/b/$D/phy"
for f in $FILES; do /bin/cp -f "$D/$f" "$S/a/$D/$f"; done
python3 "$ROOT/tools/patchgen/mkpatch-0003.py" "$SRC"
for f in $FILES; do /bin/cp -f "$D/$f" "$S/b/$D/$f"; done
cd "$S"
{
printf 'From: Matt\nSubject: [PATCH] drm/msm/dsi: 20nm PHY: keep the bootloader PHY and PLL\n\n'
printf 'Bring-up hack, not for upstream as is. There is no 20nm DSI PLL driver,\nso the display depends on the PLL the bootloader set up, powered through\nthe PHY regulator. The host PHY reset before enable, and reprogramming the\nPHY, drop it and the byte clock never starts (-EBUSY). When the PHY is\nfound enabled at probe (CTRL_0 = 0x7f), skip the reset and leave the PHY\nalone on enable/disable.\n\n---\n'
for f in $FILES; do diff -u "a/$D/$f" "b/$D/$f" || true; done
} > "$ROOT/kernel/patches/0003-drm-msm-dsi-20nm-phy-keep-bootloader-pll.patch"
echo "lines added: $(grep -c '^+[^+]' "$ROOT/kernel/patches/0003-drm-msm-dsi-20nm-phy-keep-bootloader-pll.patch")"
