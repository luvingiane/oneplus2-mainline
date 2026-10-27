#!/usr/bin/env bash
# Hands-free test turn: phone running our kernel (USB network) or in fastboot
# -> fastboot -> `fastboot -s "${OP2_SERIAL:?set OP2_SERIAL to your phone's fastboot serial}" boot <img>` (RAM only) -> wait for 172.16.42.1.
# Our kernel goes back to fastboot with a warm reset + IMEM restart reason
# 0x77665500 (LK keeps IMEM only across a warm reset).
#   scripts/next.sh out/<name>.img
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
IMG=${1:?image}
if ! timeout 2 fastboot devices | grep -q "^${OP2_SERIAL:?set OP2_SERIAL to your phone's fastboot serial}"; then
	if ping -c1 -W1 172.16.42.1 >/dev/null 2>&1; then
		python3 "$ROOT/scripts/psh.py" 'echo warm > /sys/kernel/reboot/mode; devmem 0xfe87f65c 32 0x77665500; setsid sh -c "sleep 1; reboot -f" </dev/null >/dev/null 2>&1 & echo ok' >/dev/null 2>&1
	elif adb -s "${OP2_SERIAL:?set OP2_SERIAL to your phone's fastboot serial}" get-state 2>/dev/null | grep -qE 'device|recovery'; then
		adb -s "${OP2_SERIAL:?set OP2_SERIAL to your phone's fastboot serial}" reboot bootloader
	fi
	for i in $(seq 1 30); do timeout 2 fastboot devices | grep -q "^${OP2_SERIAL:?set OP2_SERIAL to your phone's fastboot serial}" && break; sleep 2; done
fi
timeout 2 fastboot devices | grep -q "^${OP2_SERIAL:?set OP2_SERIAL to your phone's fastboot serial}" || { echo "phone not in fastboot (needs the keys)"; exit 1; }
(cd "$(dirname "$IMG")" && sha256sum -c --quiet "$(basename "$IMG" .img).sha256") || exit 1
echo "$(date +%T) fastboot -s "${OP2_SERIAL:?set OP2_SERIAL to your phone's fastboot serial}" boot $IMG"
fastboot -s "${OP2_SERIAL:?set OP2_SERIAL to your phone's fastboot serial}" boot "$IMG" 2>&1 | tail -1
for i in $(seq 1 60); do ping -c1 -W1 172.16.42.1 >/dev/null 2>&1 && { echo "$(date +%T) up"; exit 0; }; sleep 1; done
echo "$(date +%T) no network after 60 s"; exit 2
