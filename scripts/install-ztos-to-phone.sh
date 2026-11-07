#!/usr/bin/env bash
# Install a cross-built ztOS (scripts/cross-ztos.sh <dir> all) on the phone, with a backup of what it replaces.
#   scripts/install-ztos-to-phone.sh <ztOS-checkout>/ztmetro
# - stages what the Makefile's `install` target would install into a temp root (make -n, paths rewritten);
# - on the phone: tar of the files about to be replaced in /root/ztos-before-<date>.tar, then the new files;
# - systemd units are copied but NOT enabled/started (the phone decides what runs); daemon-reload only.
# The running session is not restarted here: do it with `kill $(pgrep -x ztmetro)` (greetd starts it again).
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SRC=${1:?path to the ztmetro dir (already cross-built)}
STAGE=$(mktemp -d)
cd "$SRC"
# the install recipe lines, read from the Makefile text (NOT through make: its FOREIGN check deletes the
# aarch64 executables from the tree whenever make is run on the x86 PC, even with -n); paths moved under $STAGE
awk '/^install: /{f=1;next} f&&/^[^\t]/{f=0} f&&/^\tinstall /{sub(/^\t/,"");print}' Makefile \
	| sed -E "s# (/(usr|etc)/)# $STAGE\1#g; s#-t (/(usr|etc)/)#-t $STAGE\1#g" > "$STAGE/.cmds"
grep -c '^install' "$STAGE/.cmds" >/dev/null
sh "$STAGE/.cmds"
rm -f "$STAGE/.cmds"
( cd "$STAGE" && find . -type f | sed 's#^\./##' | sort > /tmp/ztos-install-list )
echo "staged $(wc -l < /tmp/ztos-install-list) files"
D=$(date +%Y%m%d-%H%M)
tar -C "$STAGE" -cf - . | "$ROOT/scripts/op2-ssh" "cat > /tmp/ztos-new.tar"
"$ROOT/scripts/op2-ssh" "cd / && tar -cf /root/ztos-before-$D.tar \$(tar -tf /tmp/ztos-new.tar | grep -v '/\$' | sed 's#^\./##' | while read f; do [ -e \"\$f\" ] && echo \"\$f\"; done) 2>/dev/null; tar -xf /tmp/ztos-new.tar -C / && systemctl daemon-reload && echo installed; ls -l /root/ztos-before-$D.tar | cut -c20-80"
rm -rf "$STAGE"
