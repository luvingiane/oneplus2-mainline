#!/bin/sh
# hang-test.sh [regs|power]: GPU draw hang test on the phone. Hang recovery
# off, GPU held powered, gpu-steps 2 (init) then 5 in the background; after
# 8 s the status registers (and with "power" the power registers).
# Log: /root/hang-test.log, synced after each line.
L=/root/hang-test.log
log() { echo "$(cut -d' ' -f1 /proc/uptime) $*" >> $L; sync; }
: > $L
echo 4000000000 > /sys/kernel/debug/dri/1/hangcheck_period_ms
G=$(ls -d /sys/devices/platform/soc@0/*.gpu | head -1)
echo on > $G/power/control
log "gpu $G control $(cat $G/power/control) status $(cat $G/power/runtime_status)"
cd /root && ./gpu-steps 2 >> $L 2>&1; sync
log "init done, runtime $(cat $G/power/runtime_status)"
setsid ./gpu-steps 5 >> $L 2>&1 &
sleep 8
log "after 8 s: $(cat /proc/$!/wchan 2>/dev/null) runtime $(cat $G/power/runtime_status)"
[ -n "$1" ] && python3 /root/gpu-regs.py >> $L 2>&1; sync
[ "$1" = power ] && python3 /root/gpu-regs.py power >> $L 2>&1; sync
log end
