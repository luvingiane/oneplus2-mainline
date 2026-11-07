#!/bin/sh
# On the phone: keeps the modem working across its restarts (SSR). When the modem restarts, /dev/wwan0qmi0 disappears and
# rmtfs is left with the old boot's state: the new boot then stalls ("dog.c: Watchdog detects stalled initialization",
# every ~41 s) until rmtfs is restarted. So: port gone for >6 s -> restart rmtfs, run op2-modem-up again (DPM port, online,
# SIM session), restart the ztOS modem daemon (its AT port was closed with the modem).
while true; do
	sleep 3
	# a modem restart can recreate /dev/wwan0at0 faster than the check below: the daemon is then left with the old,
	# deleted node, every write fails with ENODEV and it spins at ~90% of a core (seen on B: 76 min of CPU in 6 h)
	P=$(pidof ztoscorenetworkingd)
	if [ -n "$P" ] && ls -l /proc/$P/fd 2>/dev/null | grep -q 'wwan0at.*(deleted)'; then
		echo "op2-modem-watch: the daemon holds a deleted wwan port, restarting it"
		systemctl restart ztoscorenetworking
	fi
	[ -e /dev/wwan0qmi0 ] && continue
	sleep 6
	[ -e /dev/wwan0qmi0 ] && continue
	echo "op2-modem-watch: wwan port gone, recovering"
	systemctl restart op2-rmtfs
	sleep 5
	/usr/local/bin/op2-modem-up
	systemctl restart ztoscorenetworking
	echo "op2-modem-watch: recovered"
done
