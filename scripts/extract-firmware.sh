#!/usr/bin/env bash
# Extract all proprietary firmware from the OnePlus 2 eMMC.
# Run ON THE PHONE as root (initramfs or TWRP terminal), e.g.:
#   scp -i keys/op2_ed25519 scripts/extract-firmware.sh root@172.16.44.1:/tmp/
#   ssh ... 'bash /tmp/extract-firmware.sh /tmp/fw-out'
# Then pull: scp -r root@PHONE:/tmp/fw-out firmware/extracted-A/
# Partition map (LineageOS fstab.qcom):
#   by-name/modem     -> /firmware     (vfat: image/* adsp/modem/mba/venus, etc/firmware via system)
#   by-name/bluetooth -> /bt_firmware  (vfat: BT nvm/rampatch)
#   by-name/persist   -> /persist      (ext4: wlan_mac.bin, wlan/*, factory cal)
#   by-name/system    -> /system       (ext4: etc/wifi WCNSS*, etc/firmware a420/venus/tfa/nvm)
set -u
OUT=${1:-/tmp/fw-out}
mkdir -p "$OUT"
M=/tmp/fwmnt; mkdir -p $M/{modem,bt,persist,system}
mount -o ro /dev/block/platform/soc.0/f9824900.sdhci/by-name/modem     $M/modem     2>/dev/null
mount -o ro /dev/block/platform/soc.0/f9824900.sdhci/by-name/bluetooth $M/bt        2>/dev/null
mount -o ro /dev/block/platform/soc.0/f9824900.sdhci/by-name/persist   $M/persist   2>/dev/null
mount -o ro /dev/block/platform/soc.0/f9824900.sdhci/by-name/system    $M/system    2>/dev/null
# fall back to by-partno if by-name missing
for n in modem bluetooth persist system; do
  [ -d $M/$n ] && [ -z "$(ls -A $M/$n 2>/dev/null)" ] && umount $M/$n 2>/dev/null
done
cp -r $M/system/etc/wifi        "$OUT/wifi"        2>/dev/null
cp -r $M/system/etc/firmware    "$OUT/system-fw"   2>/dev/null
cp -r $M/modem/image            "$OUT/modem-image" 2>/dev/null
cp -r $M/modem/etc              "$OUT/modem-etc"   2>/dev/null
cp -r $M/bt/*                   "$OUT/bt"          2>/dev/null
cp -r $M/persist/wlan* $M/persist/wifi* "$OUT/persist-wlan" 2>/dev/null
cp -r $M/persist/bluetooth      "$OUT/persist-bt"  2>/dev/null
cp    $M/persist/wlan_mac.bin   "$OUT/"            2>/dev/null
echo "=== tree of $OUT:"
find "$OUT" -type f | head -80
du -sh "$OUT"
