#!/usr/bin/env bash
# Puts the "phone in a pocket" changes on B (the OnePlus 2 running ztOS), over Wi-Fi:
#   - op2-sensord: proximity streamed while the screen is off, "raw near" in /run/ztoscsf-sensors/prox
#   - ztmetro: ZTMETRO_NAV_WAKE=0 (the home touch key does not wake the screen) and no wake from a pocket
# ztmetro is the session: it is replaced on disk (the old one keeps running) and the new one starts with the NEXT session
# (log out, or reboot); sensord is restarted at once. Backups next to the originals (*.before-pocket).
#   scripts/deploy-pocket-b.sh [host]        default <home LAN>
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
H=${1:-<home LAN>}
B() { ssh -F "$ROOT/keys/ssh_config" -o HostName="$H" -o ConnectTimeout=10 op2 "$@"; }
ZT=$HOME/Github_Clones/ztOS/ztmetro/ztmetro
[ -f "$ZT" ] && [ -f "$ROOT/build/op2-sensord" ] || { echo "build first: scripts/cross-ztos.sh <ztOS>/ztmetro ztmetro; scripts/build-op2-sensord.sh" >&2; exit 1; }
B 'cp -n /usr/local/bin/ztmetro /usr/local/bin/ztmetro.before-pocket'
B 'cat > /usr/local/bin/ztmetro.new && chmod 755 /usr/local/bin/ztmetro.new && mv /usr/local/bin/ztmetro.new /usr/local/bin/ztmetro' < "$ZT"
SD=$(B 'systemctl cat ztoscsf-sensord 2>/dev/null | sed -n "s/^ExecStart=//p" | head -1 | cut -d" " -f1')
[ -n "$SD" ] || SD=/usr/local/bin/op2-sensord
echo "sensord binary on B: $SD"
B "cp -n $SD $SD.before-pocket"
B "cat > $SD.new && chmod 755 $SD.new && mv $SD.new $SD" < "$ROOT/build/op2-sensord"
B 'grep -q ZTMETRO_NAV_WAKE /etc/ztos/session.env 2>/dev/null || printf "# the capacitive home key must not wake the phone in a pocket (the left touch key)\nexport ZTMETRO_NAV_WAKE=0\n" >> /etc/ztos/session.env; touch /run/hold; systemctl restart ztoscsf-sensord; sleep 3; systemctl is-active ztoscsf-sensord; tail -2 /etc/ztos/session.env'
echo "done. The new ztmetro runs from the next session start."
