#!/bin/bash
# gpu-auto2.sh <serial> <img:label:wait_s> [<img:label:wait_s> ...]
# Unattended GPU test loop, one phone. For each image: up to 3 attempts.
# An attempt is "good" when we captured the phone's ACM serial console
# (console=ttyGS0 -> /dev/ttyACM*) with real content. The phone always ends
# back in fastboot by itself: panic=10 + op2.crash=fastboot on crash, the
# op2.deadman timer if the host never reaches it, else an explicit
# "reboot -f" over the serial shell. No physical action ever needed.
set -u
cd /home/matt/oneplus2
FB="env -u LD_LIBRARY_PATH /usr/bin/fastboot"
S=$1; shift
[ "$S" = "7485b821" ] && { SSH="/tmp/assh.sh"; IP=172.16.44.1; } || { SSH="bash scripts/op2-ssh"; IP=172.16.42.1; }
OUT=/home/matt/.vibe/scratchpad/gpu-auto.out
: > "$OUT"
say() { echo "$*" | tee -a "$OUT"; }

wait_fastboot() {
	for i in $(seq 1 $(( $1 / 5 ))); do
		sleep 5
		$FB devices 2>/dev/null | grep -q "$S" && return 0
	done
	return 1
}
usbreset_all() {
	for dev in /dev/bus/usb/*/*; do
		b=${dev#/dev/bus/usb/}; b=${b//\//:}
		lsusb -s "$b" 2>/dev/null | grep -q "18d1:" && env -u LD_LIBRARY_PATH usbreset "$dev" 2>/dev/null && say "  usbreset $dev"
	done
}

run_once() { # $1 img  $2 label  $3 wait  -> returns 0 if console captured
	local img=$1 label=$2 WAIT=$3 tty before i new back CATPID LOG
	if ! wait_fastboot 150; then
		say "  no fastboot on $S: usbreset + retry"
		usbreset_all; wait_fastboot 120 || { say "  STILL NO FASTBOOT on $S"; return 1; }
	fi
	before=$(ls /dev/ttyACM* 2>/dev/null | sort)
	say "  boot $img ($(date +%T))"
	timeout 30 $FB -s "$S" boot "$img" >/dev/null 2>&1
	tty=""
	for i in $(seq 1 50); do
		sleep 2
		new=$(comm -13 <(echo "$before") <(ls /dev/ttyACM* 2>/dev/null | sort) | head -1)
		[ -n "$new" ] && { tty=$new; break; }
	done
	LOG="gemini/logs/gpuauto-${label}-$(date +%H%M%S).log"
	if [ -n "$tty" ]; then
		stty -F "$tty" raw -echo 2>/dev/null
		say "  serial $tty -> $LOG"
		timeout "$WAIT" cat "$tty" > "$LOG" 2>/dev/null &
		CATPID=$!
		for i in $(seq 1 $(( WAIT / 15 ))); do
			sleep 15
			printf 'touch /run/hold\n' > "$tty" 2>/dev/null
			timeout 5 $SSH 'touch /run/hold' 2>/dev/null
		done
	else
		say "  no ACM after 100 s — deadman will bring it back"
		: > "$LOG"
		for i in $(seq 1 $(( WAIT / 15 ))); do sleep 15; timeout 5 $SSH 'touch /run/hold' 2>/dev/null; done
	fi
	back=0
	for i in $(seq 1 $(( (WAIT + 120) / 5 ))); do
		sleep 5
		$FB devices 2>/dev/null | grep -q "$S" && { back=1; break; }
	done
	if [ "$back" = 1 ]; then
		say "  $label: back in fastboot after ~$((i*5))s"
	else
		say "  $label: reboot -f via serial/ssh"
		[ -n "$tty" ] && printf 'reboot -f\n' > "$tty" 2>/dev/null
		timeout 8 $SSH 'reboot -f' 2>/dev/null
		wait_fastboot 90 && say "  $label: back in fastboot" || { usbreset_all; wait_fastboot 90 || say "  $label: LOST (physical replug needed)"; }
	fi
	[ -n "${CATPID:-}" ] && kill $CATPID 2>/dev/null
	local lines; lines=$(wc -l < "$LOG" 2>/dev/null || echo 0)
	say "  log $LOG: $lines lines"
	if [ "$lines" -gt 40 ] && grep -aqE "gputest|op2dbg|op2boot|panic|Linux version" "$LOG" 2>/dev/null; then
		grep -aE "gputest|op2dbg|panic|lockup|NMI|Call trace|adreno|a4xx" "$LOG" | tail -15 | sed 's/^/    /' | tee -a "$OUT"
		return 0
	fi
	return 1
}

for spec in "$@"; do
	img=${spec%%:*}; rest=${spec#*:}; label=${rest%%:*}; WAIT=${rest#*:}
	say "===== $label img=$img wait=${WAIT}s ====="
	for att in 1 2 3; do
		say "--- attempt $att ($label) $(date +%T)"
		run_once "$img" "$label" "$WAIT" && break
		say "--- attempt $att gave no console; retrying"
	done
done
say "===== FINE $(date +%T) ====="
