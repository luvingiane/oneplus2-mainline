#!/bin/bash
# gpu-auto.sh <serial> <img:label:wait_s> [<img:label:wait_s> ...]
# Unattended GPU test loop on one phone:
#   - waits for fastboot on <serial> (usbreset if the port is mute)
#   - fastboot boot <img>
#   - captures the phone's ACM serial console (console=ttyGS0 -> /dev/ttyACM*)
#     to gemini/logs/gpuauto-<label>-<HHMM>.log
#   - keeps the phone alive by sending "touch /run/hold" over the serial shell
#     (and over ssh if the NCM net came up)
#   - waits for the phone to come back to fastboot (panic + op2.crash=fastboot,
#     deadman, or an explicit "reboot -f" sent over serial at the end)
#   - moves to the next image. Never needs a physical action.
set -u
cd /home/<user>/oneplus2
FB="env -u LD_LIBRARY_PATH /usr/bin/fastboot"
S=$1; shift
[ "$S" = "<phone-A>" ] && { SSH="/tmp/assh.sh"; IP=172.16.44.1; } || { SSH="bash scripts/op2-ssh"; IP=172.16.42.1; }
OUT=/home/<user>/.vibe/scratchpad/gpu-auto.out
: > "$OUT"

say() { echo "$*" | tee -a "$OUT"; }

wait_fastboot() { # $1=max seconds; returns 0 if <serial> is in fastboot
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

for spec in "$@"; do
	img=${spec%%:*}; rest=${spec#*:}; label=${rest%%:*}; WAIT=${rest#*:}
	say "===== RUN $label img=$img wait=${WAIT}s $(date +%T) ====="
	if ! wait_fastboot 150; then
		say "  no fastboot on $S: usbreset + retry"
		usbreset_all
		wait_fastboot 120 || { say "  STILL NO FASTBOOT on $S — skipping $label"; continue; }
	fi
	before=$(ls /dev/ttyACM* 2>/dev/null | sort)
	say "  booting $img"
	timeout 30 $FB -s "$S" boot "$img" >/dev/null 2>&1
	# find the new ACM port (up to 120 s)
	tty=""
	for i in $(seq 1 60); do
		sleep 2
		new=$(comm -13 <(echo "$before") <(ls /dev/ttyACM* 2>/dev/null | sort) | head -1)
		[ -n "$new" ] && { tty=$new; break; }
	done
	LOG="gemini/logs/gpuauto-${label}-$(date +%H%M).log"
	if [ -n "$tty" ]; then
		stty -F "$tty" raw -echo 2>/dev/null
		say "  serial console: $tty -> $LOG"
		timeout "$WAIT" cat "$tty" > "$LOG" 2>/dev/null &
		CATPID=$!
		# keep the phone alive + poke the shell so we see it is alive
		for i in $(seq 1 $(( WAIT / 15 ))); do
			sleep 15
			printf 'touch /run/hold\n' > "$tty" 2>/dev/null
			timeout 5 $SSH 'touch /run/hold' 2>/dev/null
		done
	else
		say "  NO ACM serial after 120 s (USB gadget never bound) — relying on deadman"
		: > "$LOG"
		for i in $(seq 1 $(( WAIT / 15 ))); do sleep 15; timeout 5 $SSH 'touch /run/hold' 2>/dev/null; done
	fi
	# wait for the phone to come back to fastboot (panic/deadman), max WAIT+150 s
	back=0
	for i in $(seq 1 $(( (WAIT + 150) / 5 ))); do
		sleep 5
		if $FB devices 2>/dev/null | grep -q "$S"; then back=1; break; fi
	done
	if [ "$back" = 1 ]; then
		say "  $label: back in fastboot after ~$((i*5))s ($(date +%T))"
	else
		say "  $label: not back after ${WAIT}s — sending reboot -f over serial/ssh"
		[ -n "$tty" ] && printf 'reboot -f\n' > "$tty" 2>/dev/null
		timeout 8 $SSH 'reboot -f' 2>/dev/null
		wait_fastboot 90 && say "  $label: back in fastboot after reboot -f" || { say "  $label: STILL not in fastboot; usbreset"; usbreset_all; wait_fastboot 90 || say "  $label: LOST (needs physical replug)"; }
	fi
	[ -n "${CATPID:-}" ] && kill $CATPID 2>/dev/null
	say "  log: $LOG ($(wc -l < "$LOG") lines)"
	grep -aE "gputest|op2dbg|panic|lockup|NMI|ERROR|warn" "$LOG" 2>/dev/null | tail -12 | sed 's/^/    /' | tee -a "$OUT"
	CATPID=""
done
say "===== FINE $(date +%T) ====="
