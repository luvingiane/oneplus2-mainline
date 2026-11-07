#!/usr/bin/env bash
# Starts the modem DSP on a phone running a kernel with OP2_MSS and talks to it through rmtfs (read-only).
#   scripts/op2-modem-test.sh <ssh_config> <host>
# Needs: research/modem-fw/{mba.mbn,modem.mdt,modem.b*} (copied from the phone's own modem partition, not published),
# build/rmtfs/rmtfs-static (scripts/build-rmtfs.sh), and a backup of modemst1/2, fsg, fsc, oem_dycnvbk, oem_stanvbk beforehand:
# rmtfs runs WITHOUT -r, so the modem writes to those partitions (modemst2 changes on every run).
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
A() { ssh -F "$1" "$2" "${@:3}"; }
A "$1" "$2" 'mkdir -p /lib/firmware/qcom/msm8994/oneplus2 /dev/disk/by-partlabel'
(cd "$ROOT/research/modem-fw" && tar -cf - mba.mbn modem.mdt modem.b*) | A "$1" "$2" 'tar -C /lib/firmware/qcom/msm8994/oneplus2 -xf -'
A "$1" "$2" 'cat > /bin/rmtfs && chmod 755 /bin/rmtfs' < "$ROOT/build/rmtfs/rmtfs-static"
A "$1" "$2" 'for p in modemst1 modemst2 fsc fsg oem_dycnvbk oem_stanvbk; do n=$(grep -l "PARTNAME=$p" /sys/class/block/mmcblk*p*/uevent | head -1 | cut -d/ -f5); ln -sf /dev/$n /dev/disk/by-partlabel/$p; done
  touch /run/hold; (rmtfs -P -v > /tmp/rmtfs.log 2>&1 &); sleep 2
  echo start > /sys/class/remoteproc/remoteproc0/state; sleep 60
  cat /sys/class/remoteproc/remoteproc0/state; ls /sys/bus/rpmsg/devices'
