#!/bin/sh
# On the phone: Slipmat's daemon starts its Electron sidecar as "electron ." with no flags; Chromium then looks for an X11
# server ("Missing X server or $DISPLAY"), the sidecar crashes (SIGTRAP + core dump) and is restarted forever, and every
# core dump costs CPU in systemd-coredump. ELECTRON_OZONE_PLATFORM_HINT is not honoured by this build, the command-line flag is.
# Keep the real binary as electron.real and put a wrapper that adds the flag in its place.
D=/usr/share/slipmat/sidecar/node_modules/electron/dist
[ -e "$D/electron.real" ] || mv "$D/electron" "$D/electron.real"
cat > "$D/electron.new" <<'WRAP'
#!/bin/sh
exec "$(dirname "$0")/electron.real" --ozone-platform=wayland "$@"
WRAP
chmod 755 "$D/electron.new" && mv "$D/electron.new" "$D/electron"
grep -q electron.real /usr/share/slipmat/INSTALLED-FILES || echo "/usr/share/slipmat/sidecar/node_modules/electron/dist/electron.real" >> /usr/share/slipmat/INSTALLED-FILES
echo "wrapper installed: $(head -c 20 $D/electron | head -1)"
