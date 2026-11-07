#!/bin/sh
# On the phone: airplane mode for the OnePlus 2's modem. Its firmware dies with a "fatal error" on AT+CFUN=4 (and on a
# deregistration) while registered, so the radio is switched off by stopping the modem remoteproc; the ADSP stays up (sensors).
#   op2-airplane on   -> flag /run/op2-airplane, voice client and watchdog stopped, modem remoteproc stopped
#   op2-airplane off  -> flag removed, modem brought up again (op2-modem: DPM port, online, SIM session), watchdog/voice back,
#                        the ztOS modem daemon restarted (it reopens the AT port; its airplane state is reset)
rp() { for r in /sys/class/remoteproc/*; do [ "$(cat $r/name)" = "$1" ] && echo $r; done; }
case $1 in
on)
	touch /run/op2-airplane
	systemctl stop op2-modem-watch op2-voice
	M=$(rp fc880000.remoteproc)
	[ "$(cat $M/state)" = running ] && echo stop > $M/state
	echo "op2-airplane: modem stopped"
	;;
off)
	rm -f /run/op2-airplane
	# Order found on B (a clean stop and start otherwise loops on "dog.c stalled initialization"): op2-modem stopped,
	# the modem started, rmtfs restarted a few seconds into its boot, and only then op2-modem (DPM, online, SIM).
	systemctl stop op2-modem
	M=$(rp fc880000.remoteproc)
	[ "$(cat $M/state)" = running ] || echo start > $M/state
	sleep 4
	systemctl restart op2-rmtfs
	sleep 3
	systemctl start op2-modem
	systemctl start op2-modem-watch op2-voice
	systemctl restart ztoscorenetworking
	echo "op2-airplane: modem started"
	;;
*) echo "usage: op2-airplane on|off" >&2; exit 2 ;;
esac
