#!/usr/bin/env bash
# Standard deploy of a ztOS SDK app (one ELF built by `ztos-sdk build`) to B, for the user `zerone`, nothing under /usr.
#   scripts/deploy-app-b.sh [--dry-run] [--perf] APP_BINARY APP_ID "Menu name" [ICON.svg]
# What it does (docs/DEPLOY-B.md, section 3): checks B answers, keeps a backup of the previous binary (*.before-<stamp>),
# installs atomically (.new + mv), verifies the sha256 against the PC, writes the .desktop with an ABSOLUTE Exec, installs the
# icon, clears the app log, asks the shell to reread the app list. It never starts the app (ssh has no session environment:
# FD_MESA_DEBUG=sysmem etc.; the owner opens it from the menu). --perf also writes "<name> (perf)", which starts it with ZUNE_PERF=1.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DRY=0; PERF=0
while [ $# -gt 0 ]; do case $1 in --dry-run) DRY=1; shift;; --perf) PERF=1; shift;; *) break;; esac; done
BIN=${1:?APP_BINARY}; ID=${2:?APP_ID}; NAME=${3:?menu name}; ICON=${4:-}
B_HOST=${B_HOST:-<home LAN>}
STAMP=$(date +%Y%m%d-%H%M)
[ -f "$BIN" ] || { echo "no such binary: $BIN" >&2; exit 1; }
file "$BIN" | grep -q "ARM aarch64" || { echo "$BIN is not an aarch64 ELF" >&2; exit 1; }
B() { ssh -F "$ROOT/keys/ssh_config" -o ConnectTimeout=10 -o HostName="$B_HOST" op2 "$@"; }
B 'touch /run/hold; uptime -p' >/dev/null || { echo "B does not answer on $B_HOST (Wi-Fi may be asleep: ask the owner, try again; USB is 172.16.42.1)" >&2; exit 1; }
A=/home/zerone/.local/share/ztos/apps; D=/home/zerone/.local/share/applications; I=/home/zerone/.local/share/icons/hicolor/scalable/apps
echo "free space: $(B "df -h / | tail -1 | awk '{print \$4}'")  app running: $(B "ps -u zerone -o args= | grep -c '[.]local/share/ztos/apps/$ID'")  (close it to see the new build)"
PCSUM=$(sha256sum "$BIN" | cut -d' ' -f1)
if [ $DRY = 1 ]; then echo "dry run: would install $BIN ($(stat -c %s "$BIN") bytes, ${PCSUM:0:16}) as $A/$ID, backup *.before-$STAMP"; exit 0; fi
B "mkdir -p $A $D $I; [ -e $A/$ID ] && cp -p $A/$ID $A/$ID.before-$STAMP || true"
B "cat > $A/$ID.new && chmod 755 $A/$ID.new && mv -f $A/$ID.new $A/$ID" < "$BIN"
BSUM=$(B "sha256sum $A/$ID" | cut -d' ' -f1)
[ "$PCSUM" = "$BSUM" ] || { echo "HASH MISMATCH: PC ${PCSUM:0:16} / B ${BSUM:0:16}: restore $A/$ID.before-$STAMP" >&2; exit 1; }
if [ -n "$ICON" ]; then
	# install the icon under its REAL extension: the shell's glyph loader
	# picks the decoder by extension (.png -> gdk-pixbuf, .svg -> librsvg);
	# a png saved as .svg fails to parse and the app falls back to a note
	case "$(file -b --mime-type "$ICON")" in
		image/png) E=png ;;
		*) E=svg ;;
	esac
	B "rm -f $I/$ID.svg $I/$ID.png && cat > $I/$ID.$E" < "$ICON"
fi
desktop() { # file, name, exec
	B "cat > $D/$1.desktop" <<EOD
[Desktop Entry]
Type=Application
Name=$2
Exec=$3
Icon=$ID
Terminal=false
StartupWMClass=ztos.$ID
Categories=Audio;Music;
X-ZtOS-Id=$ID
EOD
}
desktop "$ID" "$NAME" "$A/$ID"
[ $PERF = 1 ] && desktop "$ID-perf" "$NAME (perf)" "sh -c \"ZUNE_PERF=1 exec $A/$ID\""
B "rm -f /home/zerone/.local/state/ztos/$ID.log; chown -R zerone:zerone /home/zerone/.local; runuser -u zerone -- sh -c 'printf \"apps\n\" > /run/user/1000/ztmetro.ctl'"
echo "deployed $ID: ${BSUM:0:16} (same on PC and B); backup $A/$ID.before-$STAMP; open it from the menu, logs in ~/.local/state/ztos/$ID.log"
