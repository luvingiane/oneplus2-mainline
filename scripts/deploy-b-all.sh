#!/usr/bin/env bash
# Everything pending for B, in one go (7/11): backup, install, logo, reboot, check.
#   scripts/deploy-b-all.sh [--dry-run] [--no-airplane-test]
# 1. checks: B answers on ssh, the binaries are built, the logo builds from B's OWN LOGO dump
# 2. backups (read only): B's LOGO partition -> backups/logo-B.img, the binaries it replaces stay next to them (*.before-pocket)
# 3. install over ssh: ztmetro (screenshot = power + volume UP, volume keys with the screen off, no wake from the touch Home
#    key or from a pocket), op2-sensord (proximity streamed with the screen off), ZTMETRO_NAV_WAKE=0 in /etc/ztos/session.env
# 4. the logo: `fastboot flash LOGO` (the name must be upper case), checked by hash after the reboot
# 5. reboot from flash (kernel s362) -> the new ztmetro runs in the fresh session; checks (services, modem, environment, logo hash)
#    and the airplane mode test (airplane on -> AT+CFUN? 4 and DMS low power -> airplane off), always left OFF.
# --dry-run stops after step 1 and the read-only dump: nothing on the phone is written.
# Rollback: fastboot flash LOGO backups/logo-B.img ; the *.before-pocket files over their originals ; fastboot flash boot
# backups/boot-B-s332-before-s362.img (only if the kernel is the problem).
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DRY=0; AIR=1
for a in "$@"; do case $a in --dry-run) DRY=1 ;; --no-airplane-test) AIR=0 ;; *) echo "unknown option $a" >&2; exit 2 ;; esac; done
HOST_ALIAS=${HOST_ALIAS:-op2}              # ssh_config alias (HostName overridden by B_HOST when set)
B_HOST=${B_HOST-<home LAN>}
FB_ID=${FB_ID:-<phone-B>}                  # B's fastboot serial; A's is <phone-A>
DUMP=${DUMP:-$ROOT/backups/logo-B.img}
LOGOPART=LOGO
ZT=${ZT:-$HOME/Github_Clones/ztOS/ztmetro}
OUT=$ROOT/out/logo-deploy; mkdir -p "$OUT"
log() { echo "[$(date +%H:%M:%S)] $*"; }
B() { local o=(-F "$ROOT/keys/ssh_config" -o ConnectTimeout=10); [ -n "$B_HOST" ] && o+=(-o HostName="$B_HOST"); ssh "${o[@]}" "$HOST_ALIAS" "$@"; }

log "1/5 checks"
if ! B 'touch /run/hold 2>/dev/null; uname -r' >/dev/null 2>&1; then
	# the Wi-Fi address changes: try the ssh_config one (USB networking, 172.16.42.1)
	[ -n "$B_HOST" ] && log "  $B_HOST does not answer, trying the USB address" && B_HOST=""
	B 'touch /run/hold 2>/dev/null; uname -r' >/dev/null 2>&1 || { echo "B does not answer on ssh (Wi-Fi nor USB): give its address as B_HOST=..." >&2; exit 1; }
fi
if [ $DRY = 0 ]; then
	[ -f "$ZT/ztmetro" ] || { echo "ztmetro not built" >&2; exit 1; }
	[ -f "$ROOT/build/op2-sensord" ] || { echo "op2-sensord not built" >&2; exit 1; }
	[ -n "$(find "$ZT/ztmetro.c" -newer "$ZT/ztmetro" 2>/dev/null)" ] && { echo "ztmetro.c is newer than the binary: rebuild (scripts/cross-ztos.sh $ZT ztmetro)" >&2; exit 1; }
fi
PART=$(B "grep -l PARTNAME=$LOGOPART /sys/class/block/*/uevent | head -1 | cut -d/ -f5")
[ -n "$PART" ] || { echo "no $LOGOPART partition on the phone" >&2; exit 1; }
SIZE=$(B "echo \$((\$(cat /sys/class/block/$PART/size) * 512))")
[ "$SIZE" = 16777216 ] || { echo "$LOGOPART is $SIZE bytes, expected 16777216" >&2; exit 1; }
log "  $LOGOPART = /dev/$PART, 16 MiB"

log "2/5 backup of the LOGO partition (read only)"
B "cat /dev/$PART" > "$DUMP"; chmod 600 "$DUMP"
H1=$(sha256sum "$DUMP" | cut -d' ' -f1); H2=$(B "sha256sum /dev/$PART" | cut -d' ' -f1)
[ "$H1" = "$H2" ] || { echo "dump hash differs from the partition ($H1 / $H2)" >&2; exit 1; }
[ "$(head -c 8 "$DUMP")" = "SPLASH!!" ] || { echo "the dump is not a SPLASH logo container" >&2; exit 1; }
log "  $DUMP sha256 ${H1:0:16}"
SAME=no; [ -f "$ROOT/backups/logo-A.img" ] && [ "$H1" = "$(sha256sum "$ROOT/backups/logo-A.img" | cut -d' ' -f1)" ] && SAME=yes
log "  same as A's original dump: $SAME"

log "  building the logo from THIS dump (variant A: OnePlus mark + Arch logo, 460 px, 3 grey levels)"
python3 -I "$ROOT/tools/boot-logo/build_arch_logo.py" "$DUMP" "$OUT" --variant a --width 460 --levels 3 \
	--logo "$ROOT/build/boot-logo/archlinux-logo-white-1200dpi.png" | sed 's/^/  /'
IMG=$OUT/logo-arch-a.img
[ "$(stat -c %s "$IMG")" = 16777216 ] || { echo "the logo image is not 16 MiB" >&2; exit 1; }
if [ $DRY = 1 ]; then
	log "dry run: stops here. Plan: install ztmetro + op2-sensord + session.env, flash $LOGOPART from $IMG, reboot, check."
	exit 0
fi

log "3/5 install over ssh"
"$ROOT/scripts/deploy-pocket-b.sh" "$B_HOST"

log "4/5 the logo: B to the bootloader and the flash"
B 'touch /run/hold; reboot bootloader' >/dev/null 2>&1 || true
for i in $(seq 1 60); do fastboot devices | grep -q "$FB_ID" && break; sleep 3; done
fastboot devices | grep -q "$FB_ID" || { echo "B did not reach fastboot" >&2; exit 1; }
fastboot -s "$FB_ID" flash "$LOGOPART" "$IMG"
log "  flashed; rebooting from flash"
fastboot -s "$FB_ID" reboot

log "5/5 after the reboot"
for i in $(seq 1 80); do B 'echo up' 2>/dev/null | grep -q up && break; sleep 4; done
B 'echo up' 2>/dev/null | grep -q up || { echo "B did not come back on ssh in 5 min: check the screen" >&2; exit 1; }
sleep 45
B 'touch /run/hold
echo "uptime: $(uptime -p)  kernel: $(uname -v | cut -c1-30)"
echo "services: $(systemctl is-active op2-rmtfs op2-modem op2-voice op2-modem-watch ztoscorenetworking ztoscsf-sensord zrnperfd | tr "\n" " ")"
P=$(pidof ztmetro | cut -d" " -f1); echo "ztmetro pid $P, env: $(tr "\0" "\n" < /proc/$P/environ | grep -E "^ZTMETRO_(NAV_WAKE|POCKET)" | tr "\n" " ")"
echo "ztmetro binary: $(ls -l --time-style=+%H:%M /usr/local/bin/ztmetro | awk "{print \$6}"), running since $(ps -o lstart= -p $P)"
echo "modem: $(grep -E "^(sim|registered|tech|bars|airplane)=" /run/ztoscorenetworking/status | tr "\n" " ")"
echo "cpusets: user=$(cat /sys/fs/cgroup/user.slice/cpuset.cpus.effective)"' || true
HB=$(B "sha256sum /dev/$PART" | cut -d' ' -f1); HI=$(sha256sum "$IMG" | cut -d' ' -f1)
if [ "$HB" = "$HI" ]; then log "  LOGO on B = the new image (${HI:0:16})"; else log "  !!! LOGO hash differs: ${HB:0:16} vs ${HI:0:16}"; fi
if [ $AIR = 1 ]; then
	log "  airplane mode test (the radio is off for ~25 s, then on again)"
	B 'printf "airplane on\n" > /run/ztoscorenetworking.ctl; sleep 14
echo "airplane on:  $(grep -E "^(airplane|registered|bars)=" /run/ztoscorenetworking/status | tr "\n" " ")"
printf "airplane off\n" > /run/ztoscorenetworking.ctl; sleep 20
echo "airplane off: $(grep -E "^(airplane|registered|bars|tech)=" /run/ztoscorenetworking/status | tr "\n" " ")"' || true
fi
log "done. Look at B: the Arch logo shows at the NEXT power-on; the key/volume/pocket changes are live in this session."
