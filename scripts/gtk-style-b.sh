#!/usr/bin/env bash
# Puts the ztOS style wrapper's GTK 3 and 4 themes (branch feat/style-wrapper, ~/Github_Clones/ztOS-style-wrapper) on B, for the
# user only (nothing under /usr), and can put everything back.
#   scripts/gtk-style-b.sh metro|dotmatrix|restore   [B host, default from B_HOST]
# GTK 3 (and GTK 4 apps that are not libadwaita): GSettings gtk-theme + ~/.local/share/themes/ztos-<style>.
# libadwaita apps (GTK 4) ignore the theme name: ~/.config/gtk-4.0/gtk.css points at the theme's gtk-4.0/gtk.css.
# The first run keeps a backup of ~/.config/gtk-3.0, ~/.config/gtk-4.0 and the old gtk-theme in ~/.config/gtk-backup-ztos.tgz.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
W=${WRAPPER:-$HOME/Github_Clones/ztOS-style-wrapper}
B_HOST=${B_HOST:-<home LAN>}
STYLE=${1:?metro|dotmatrix|restore}
B() { ssh -F "$ROOT/keys/ssh_config" -o ConnectTimeout=10 -o HostName="$B_HOST" op2 "$@"; }
ENV="runuser -u zerone -- env HOME=/home/zerone XDG_RUNTIME_DIR=/run/user/1000 DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/1000/bus"
case $STYLE in
metro|dotmatrix)
	[ -d "$W/wrapper/share/themes/ztos-$STYLE" ] || { echo "no theme at $W/wrapper/share/themes/ztos-$STYLE" >&2; exit 1; }
	B 'touch /run/hold; cd /home/zerone; [ -e .config/gtk-backup-ztos.tgz ] || { '"$ENV"' gsettings get org.gnome.desktop.interface gtk-theme > .config/gtk-theme-before; tar -czf .config/gtk-backup-ztos.tgz .config/gtk-3.0 .config/gtk-4.0 .config/gtk-theme-before; chown zerone:zerone .config/gtk-backup-ztos.tgz .config/gtk-theme-before; echo "backup written"; }; mkdir -p .local/share/themes; chown zerone:zerone .local .local/share .local/share/themes'
	tar -C "$W/wrapper/share/themes" -cf - "ztos-$STYLE" | B 'tar -C /home/zerone/.local/share/themes --no-same-owner -xf - && chown -R zerone:zerone /home/zerone/.local/share/themes'
	B "$ENV"' sh -c "
		cd ~/.config/gtk-4.0 && mkdir -p ../gtk-4.0-old && for f in gtk.css gtk-dark.css; do [ -e \$f ] || [ -L \$f ] && mv -f \$f ../gtk-4.0-old/ 2>/dev/null; done
		ln -s ~/.local/share/themes/ztos-'"$STYLE"'/gtk-4.0/gtk.css gtk.css
		gsettings set org.gnome.desktop.interface gtk-theme ztos-'"$STYLE"'
		gsettings get org.gnome.desktop.interface gtk-theme; ls -l ~/.config/gtk-4.0 | tail -4"'
	echo "done: restart the GTK apps to see it";;
restore)
	B "$ENV"' sh -c "
		cd ~/.config; [ -e gtk-backup-ztos.tgz ] || { echo no backup; exit 1; }
		rm -rf gtk-3.0 gtk-4.0 gtk-4.0-old; tar -xzf gtk-backup-ztos.tgz -C ~/
		gsettings set org.gnome.desktop.interface gtk-theme \"\$(sed s/^.// gtk-theme-before | sed s/.\$//)\"; gsettings get org.gnome.desktop.interface gtk-theme"';;
*) echo "metro|dotmatrix|restore" >&2; exit 2;;
esac
