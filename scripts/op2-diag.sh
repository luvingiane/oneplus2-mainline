#!/usr/bin/env bash
# op2-diag.sh — diagnostica completa del telefono B (ztOS su 172.16.42.1) via SSH.
# Uso:  scripts/op2-diag.sh [sezione]   (sezioni: all kernel drm gpu input fb mem proc net batt)
# Login: chiave ~/.ssh/id_op2_owner (installata su B), fallback keys/ssh_config.
set -u
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SSH="ssh -i $HOME/.ssh/id_op2_owner -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o LogLevel=ERROR -o ConnectTimeout=5 root@172.16.42.1"
if ! $SSH true 2>/dev/null; then SSH="$ROOT/scripts/op2-ssh"; fi
S=${1:-all}
run() { echo; echo "===== $1 ====="; $SSH "$2" 2>&1 | head -"${3:-40}"; }

[ "$S" = all ] || [ "$S" = kernel ] && run "kernel/uptime" 'uname -a; uptime; dmesg | tail -25' 40
[ "$S" = all ] || [ "$S" = kernel ] && run "dmesg errori display/gpu" 'dmesg | grep -iE "dsi_err|pp done|mdp5|adreno|a4xx|SError|lockup|panic|bug" | tail -30' 40
[ "$S" = all ] || [ "$S" = drm ] && run "drm cards/connector" 'ls /dev/dri/; for c in /sys/class/drm/card1-*; do echo "$c: $(cat $c/status 2>/dev/null) enabled=$(cat $c/enabled 2>/dev/null)"; done; cat /sys/class/drm/card1-DSI-1/modes 2>/dev/null | head -2' 15
[ "$S" = all ] || [ "$S" = drm ] && run "interrupts dsi/mdp" 'grep -E "dsi|mdp|mdss" /proc/interrupts' 8
[ "$S" = all ] || [ "$S" = drm ] && run "frame rate (10s)" 'A=$(awk "/dsi_isr/{print \$2}" /proc/interrupts); sleep 10; B=$(awk "/dsi_isr/{print \$2}" /proc/interrupts); echo "dsi_isr/10s=$((B-A))"' 5
[ "$S" = all ] || [ "$S" = gpu ] && run "gpu" 'ls /dev/dri/; cat /sys/class/devfreq/fdb00000.gpu/cur_freq 2>/dev/null; cat /sys/class/drm/card1/device/gpu_busy 2>/dev/null; dmesg | grep -iE "adreno|a4xx|hw_init|op2_gpu_phys" | tail -10' 20
[ "$S" = all ] || [ "$S" = input ] && run "input/touch" 'ls /dev/input/; cat /proc/bus/input/devices | grep -A2 -iE "synaptics|rmi|s3320" | head -12; grep -c rmi4 /proc/interrupts' 20
[ "$S" = all ] || [ "$S" = fb ] && run "fb0" 'cat /sys/class/graphics/fb0/virtual_size; cat /sys/class/graphics/fb0/bits_per_pixel; dd if=/dev/fb0 bs=1M count=8 2>/dev/null | md5sum' 6
[ "$S" = all ] || [ "$S" = mem ] && run "cpu/mem" 'grep -c ^processor /proc/cpuinfo; grep MHz /proc/cpuinfo | sort | uniq -c; free -m | head -2; cat /sys/devices/system/cpu/cpu*/cpufreq/scaling_cur_freq 2>/dev/null | sort | uniq -c' 20
[ "$S" = all ] || [ "$S" = proc ] && run "ztmetro" 'P=$(pgrep -x ztmetro|head -1); echo pid=$P; tr "\0" "\n" </proc/$P/environ 2>/dev/null | grep -E "WLR|FD_MESA|LIBGL|ZTMETRO"; ps -o pid,pcpu,etime,comm -p $P 2>/dev/null; systemctl is-active op2-kick 2>/dev/null' 10
[ "$S" = all ] || [ "$S" = net ] && run "rete" 'ip -br addr | grep usb; ip route | head -3; ping -c1 -W1 8.8.8.8 >/dev/null 2>&1 && echo "internet OK" || echo "no internet"' 8
[ "$S" = all ] || [ "$S" = batt ] && run "batteria" 'cat /sys/class/power_supply/battery/status 2>/dev/null; cat /sys/class/power_supply/battery/capacity 2>/dev/null; cat /sys/class/power_supply/battery/charge_now 2>/dev/null' 5
echo; echo "diag completata $(date +%T)"
