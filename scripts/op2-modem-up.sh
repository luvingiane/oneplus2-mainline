#!/bin/sh
# On the phone (needs a kernel with OP2_MSS OP2_ADSP + CONFIG_WWAN/RPMSG_WWAN_CTRL): brings the modem to "registered".
#   rmtfs (raw modem partitions) -> modem + ADSP remoteproc -> DPM Open Port (opens DATA5_CNTL = /dev/wwan0qmi0)
#   -> DMS operating mode online -> UIM provisioning of the USIM.
# Needs in PATH: rmtfs, qrtr-lookup, qmi-sns, qmux (static aarch64, scripts/build-rmtfs.sh, build-qmi-sns.sh, build-qmux.sh)
# and /lib/firmware/qcom/msm8994/oneplus2/{mba.mbn,modem.mdt,modem.b*,adsp.mbn} (from the phone's own partitions, not published).
# AT ports then answer on /dev/wwan0at0 and /dev/wwan0at1.
PL=/dev/disk/by-partlabel
mkdir -p $PL
for p in modemst1 modemst2 fsc fsg oem_dycnvbk oem_stanvbk; do
	n=$(grep -l "PARTNAME=$p" /sys/class/block/mmcblk*p*/uevent | head -1 | cut -d/ -f5)
	[ -n "$n" ] && ln -sf /dev/$n $PL/$p
done
pidof rmtfs >/dev/null || { rmtfs -P > /run/rmtfs.log 2>&1 & sleep 2; }
rp() { for r in /sys/class/remoteproc/*; do [ "$(cat $r/name)" = "$1" ] && echo $r; done; }
M=$(rp fc880000.remoteproc); D=$(rp adsp)
[ "$(cat $M/state)" = running ] || echo start > $M/state
sleep 8
[ "$(cat $D/state)" = running ] || echo start > $D/state
# DPM (service 47) appears on the router once the modem has booted
for i in $(seq 1 60); do
	L=$(qrtr-lookup 2>/dev/null | awk '$1==47{print $4, $5; exit}')
	[ -n "$L" ] && break
	sleep 3
done
[ -n "$L" ] || { echo "DPM service not found" >&2; exit 1; }
set -- $L
# TLV 0x10: 1 port, name "DATA5_CNTL" (1-byte length prefix), endpoint type 4 (embedded), interface 1
[ -e /dev/wwan0qmi0 ] || qmi-sns $1 $2 20 10:010a44415441355f434e544c0400000001000000 >/dev/null
for i in $(seq 1 20); do [ -e /dev/wwan0qmi0 ] && break; sleep 1; done
[ -e /dev/wwan0qmi0 ] || { echo "no /dev/wwan0qmi0" >&2; exit 1; }
# op2-voice keeps /dev/wwan0qmi0 open (the port is exclusive): let it go while this script uses it
systemctl stop op2-voice 2>/dev/null
qmux /dev/wwan0qmi0 online
sleep 3
qmux /dev/wwan0qmi0 provision
systemctl start --no-block op2-voice 2>/dev/null
