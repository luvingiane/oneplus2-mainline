#!/usr/bin/env bash
# OnePlus 2: avvia la TA "fingerprints" nel TrustZone (kernel con OP2_FPCTZ, patch 0160) e invia un comando.
#   scripts/fpc-tz-start.sh <ssh_config> <host> [comando hex...]     es. ... op2a "2d 00 00 00"
# Prerequisito: i blob in research/fpc-blobs/images/{cmnlib,fingerprints}.img (mdt+b00..b03 concatenati;
# mdt = 6748 byte per entrambi). ATTENZIONE: carica codice nel TrustZone; alcuni comandi (es. 0x1f selftest)
# hanno fatto cadere il telefono. Sequenza verificata su A il 5/11: power -> region -> lib -> app (app_id 3).
set -euo pipefail
CFG=$1 HOST=$2; shift 2
IMG=$(dirname "$0")/../research/fpc-blobs/images
S() { timeout "${T:-90}" ssh -F "$CFG" "$HOST" "$@"; }
D=/sys/kernel/debug/op2-fpc-tz
S "mount -t debugfs none /sys/kernel/debug 2>/dev/null; echo power > $D/ctl; cat $D/log"; echo
S "echo 2 > /sys/module/op2_fpc_tz/parameters/types_region; echo region > $D/ctl; cat $D/log"; echo
S "cat > $D/lib.bin" < "$IMG/cmnlib.img"
S "echo 'lib 6748' > $D/ctl; cat $D/log"; echo
S "cat > $D/app.bin" < "$IMG/fingerprints.img"
S "echo 'app 6748' > $D/ctl; cat $D/log"; echo
if [ $# -gt 0 ]; then
	S "echo 'send $*' > $D/ctl; cat $D/log; echo; od -An -tx1 -N96 $D/rsp"
fi
