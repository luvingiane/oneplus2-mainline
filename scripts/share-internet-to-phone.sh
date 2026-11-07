#!/usr/bin/env bash
# Dà internet a un telefono collegato via USB (rete 172.16.42.0/24) attraverso questo PC, in attesa del Wi-Fi.
#   sudo bash scripts/share-internet-to-phone.sh start     (attiva)
#   sudo bash scripts/share-internet-to-phone.sh stop      (toglie tutto: forwarding e regole)
# Cosa fa (e nient'altro): net.ipv4.ip_forward=1 e una tabella nft "op2share" con il masquerade della rete del
# telefono verso l'uscita del PC. `stop` rimette ip_forward com'era e cancella la tabella. Niente è permanente:
# al riavvio del PC sparisce tutto.
set -euo pipefail
[ "$(id -u)" = 0 ] || { echo "serve root: sudo bash $0 start|stop" >&2; exit 1; }
NET=172.16.42.0/24
STATE=/run/op2share.forward
case "${1:-}" in
start)
	cat /proc/sys/net/ipv4/ip_forward > "$STATE"
	sysctl -qw net.ipv4.ip_forward=1
	nft delete table ip op2share 2>/dev/null || true
	nft -f - <<EOF
table ip op2share {
	chain post {
		type nat hook postrouting priority srcnat; policy accept;
		ip saddr $NET oifname != "enp2s0f0u*" masquerade
	}
}
EOF
	echo "attivo: il telefono (172.16.42.1) esce da questo PC. 'stop' per toglierlo."
	;;
stop)
	nft delete table ip op2share 2>/dev/null || true
	[ -f "$STATE" ] && sysctl -qw net.ipv4.ip_forward="$(cat "$STATE")" && rm -f "$STATE"
	echo "tolto."
	;;
*)
	echo "uso: sudo bash $0 start|stop" >&2; exit 2 ;;
esac
