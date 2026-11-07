#!/usr/bin/env bash
# Logs B's proximity readings with the screen OFF, to calibrate the near/far thresholds: cover the sensor (top, by the earpiece)
# with a finger, then take it away. Prints "time raw near" for N seconds (default 40).
#   scripts/prox-log-b.sh [host] [seconds]
H=${1:-<home LAN>}; N=${2:-40}
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
ssh -F "$ROOT/keys/ssh_config" -o HostName="$H" -o ConnectTimeout=10 op2 "touch /run/hold; printf 'screen off\n' > /run/ztoscsf-sensord.ctl; i=0; last=''; while [ \$i -lt $((N*4)) ]; do v=\$(cat /run/ztoscsf-sensors/prox 2>/dev/null); [ \"\$v\" != \"\$last\" ] && echo \"\$(date +%T) \$v\"; last=\$v; i=\$((i+1)); sleep 0.25; done; printf 'screen on\n' > /run/ztoscsf-sensord.ctl"
