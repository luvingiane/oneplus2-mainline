#!/usr/bin/env bash
# Apply the OnePlus 2 bits (rootfs-overlay/ + the computer's ssh key) to the
# ztOS system on the phone's userdata partition, from our initramfs over ssh.
#   scripts/ztos-op2-overlay.sh
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
PUB=$(cat "$ROOT"/keys/*.pub | head -1)
tar -C "$ROOT/rootfs-overlay" -cf - . | "$ROOT/scripts/op2-ssh" "
set -e
mkdir -p /mnt/ztos
mountpoint -q /mnt/ztos || mount -t ext4 /dev/mmcblk1p43 /mnt/ztos
tar -C /mnt/ztos -xf - --no-same-owner
chown 0:0 -R /mnt/ztos/etc/NetworkManager/system-connections /mnt/ztos/etc/fstab /mnt/ztos/etc/ztos/session.env /mnt/ztos/etc/systemd/logind.conf.d
chmod 600 /mnt/ztos/etc/NetworkManager/system-connections/usb0.nmconnection
chown 0:0 /mnt/ztos/etc/sudoers.d/99-op2-reboot && chmod 0440 /mnt/ztos/etc/sudoers.d/99-op2-reboot
for h in /mnt/ztos/root /mnt/ztos/home/zerone; do
	mkdir -p \$h/.ssh; echo '$PUB' > \$h/.ssh/authorized_keys; chmod 700 \$h/.ssh; chmod 600 \$h/.ssh/authorized_keys
done
chown -R 1000:1000 /mnt/ztos/home/zerone/.ssh
sync; umount /mnt/ztos; echo overlay applied
"
