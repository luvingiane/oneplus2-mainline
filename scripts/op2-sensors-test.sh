#!/usr/bin/env bash
# Motion sensors through the ADSP sensor core (SSC): serves the sensor registry from the AP and asks SNS_SMGR for the sensor list.
#   scripts/op2-sensors-test.sh <ssh_config> <host>        (kernel with OP2_ADSP, ADSP running; tested on phone A only)
# Needs: build/rmtfs/snsreg/sns-reg (github.com/mainline-moto-X4-payton/sns-reg, GPL-3, built static with
# scripts/build-sns-reg.sh), research/ssc/sensors/sns.reg (copied from the phone's own /persist/sensors, not published),
# build/qmi-sns (scripts/build-qmi-sns.sh) and build/rmtfs/qrtr-lookup.
set -euo pipefail
ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
A() { ssh -F "$1" "$2" "${@:3}"; }
G=$ROOT/build/sns-reg-generator   # x86 build of generator.c + map.c from the sns-reg sources
"$G" "$ROOT/research/ssc/sensors/sns.reg" > "$ROOT/build/registry.conf"
A "$1" "$2" 'mkdir -p /etc/sns-reg.d; cat > /etc/sns-reg.d/registry.conf' < "$ROOT/build/registry.conf"
A "$1" "$2" 'cat > /bin/sns-reg && chmod 755 /bin/sns-reg' < "$ROOT/build/sns-reg"
A "$1" "$2" 'cat > /bin/qmi-sns && chmod 755 /bin/qmi-sns' < "$ROOT/build/qmi-sns"
A "$1" "$2" 'touch /run/hold; (sns-reg > /tmp/sns-reg.log 2>&1 &); sleep 5; tail -3 /tmp/sns-reg.log
  qrtr-lookup | grep -iE "sensor|registry"; qmi-sns 5 10 0001; qmi-sns 5 10 0005'
