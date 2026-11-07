#!/bin/bash
# gputest.sh <serial> <img> <label> [wait_s]
# Boots img on the device, pushes fw, triggers dd on card1, polls 1s
# (clk_summary + devmem RBBM_STATUS + dmesg -c) until death or wait_s.
# Log: gemini/logs/gputest-<label>-<HHMM>.log
set -u
cd /home/<user>/oneplus2
SERIAL=$1; IMG=$2; LABEL=$3; WAIT=${4:-100}
if [ "$SERIAL" = "<phone-A>" ]; then SSH="/tmp/assh.sh"; IP=172.16.44.1; else SSH="bash scripts/op2-ssh"; IP=172.16.42.1; fi
LOG="gemini/logs/gputest-${LABEL}-$(date +%H%M).log"
{
echo "== gputest $LABEL serial=$SERIAL img=$IMG wait=${WAIT}s"
# wait for fastboot
for i in $(seq 1 12); do sleep 5; env -u LD_LIBRARY_PATH /usr/bin/fastboot devices 2>/dev/null | grep -q "$SERIAL" && break; done
env -u LD_LIBRARY_PATH /usr/bin/fastboot devices
timeout 20 env -u LD_LIBRARY_PATH /usr/bin/fastboot -s "$SERIAL" boot "$IMG" 2>&1 | tail -1
ok=0
for i in $(seq 1 25); do sleep 6; if ping -c1 -W2 $IP >/dev/null 2>&1; then ok=1; break; fi; done
echo "alive_after_boot=$ok"
[ $ok = 1 ] || exit 0
for f in a420_pfp.fw a420_pm4.fw; do cat firmware/qcom/$f | timeout 20 $SSH "mkdir -p /lib/firmware/qcom; cat > /lib/firmware/qcom/$f" 2>/dev/null; done
echo "fw pushed"
timeout 15 $SSH 'nohup dd if=/dev/dri/card1 of=/dev/null bs=4096 count=1 >/dev/null 2>&1 &' 2>/dev/null
echo "trigger at $(date +%T)"
for i in $(seq 1 $WAIT); do
  sleep 1
  if ping -c1 -W1 $IP >/dev/null 2>&1; then
    echo "--- t=${i}s VIVO"
    timeout 6 $SSH 'grep -E "oxili_gfx3d_clk |oxilicx_ahb_clk |ocmemgx_clk |mmssnoc_ahb_clk |oxili_rbbmtimer_clk " /sys/kernel/debug/clk/clk_summary 2>/dev/null; echo "GDSC_GX=$(devmem 0xfc404024 2>&1) GDSC_CX=$(devmem 0xfc404034 2>&1)"; grep -iE "s2|pmi8994_s2" /sys/kernel/debug/regulator/regulator_summary 2>/dev/null | head -4; devmem 0xfdb00644 2>&1; dmesg -c 2>/dev/null | tail -8' 2>/dev/null
  else
    echo "--- t=${i}s MORTO ($(date +%T))"
    break
  fi
done
ping -c1 -W2 $IP >/dev/null 2>&1 && echo "RESULT: VIVO dopo ${WAIT}s" || echo "RESULT: MORTO"
} > "$LOG" 2>&1
echo "log: $LOG"
tail -5 "$LOG"
