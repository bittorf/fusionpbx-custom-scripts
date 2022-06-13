#!/bin/sh

LOG='/home/ejbw/logfile_inet.txt'
MARKER='/tmp/inet_bad.marker'

ping_ok()
{
	local host="$1"

	local maxtry=10
	local i=0

	while [ $i -lt $maxtry ]; do {
		if ping -c1 -w1 "$host" >/dev/null 2>/dev/null; then
			return 0
		else
			sleep 1
			i=$(( i + 1 ))
		fi
	} done

	false
}

check_inet()
{
	local list='84.38.67.43 8.8.8.8 8.8.4.4'
	local ip

	for ip in $list; do {
		ping_ok "$ip" && return 0
	} done

	false
}

if check_inet; then
	if [ -f "$MARKER" ]; then
		{
			echo "### $( date ) - OK/recover"
			ip address show dev eth0
			echo "$( date ) - OK"
		} >>"$LOG"

		rm -f "$MARKER"
		logger -s "$0:ok_again_after_failure"
	else
		case "$( ip -o link show dev eth1 )" in
			*" state UP "*)
				true

				# see /etc/network/interfaces
				ping_ok "10.10.35.42"   || ip route add 10.10.0.0/16 via 172.17.0.2 dev eth1	# wifi-network
				ping_ok "192.168.0.245" || ip route add 192.168.0.0/24 via 172.17.0.1		# reithaus NEU via UTM
				ping_ok "192.168.112.2" || ip route add 192.168.112.0/24 via 172.17.0.1		# mininet J2-dach
			;;
			*)
				ping_ok 172.17.0.82 || echo "$( date ) | eth1 down" >>"$LOG"
				ip link set dev eth1 up
				ping_ok 172.17.0.82 && echo "$( date ) | eth1 up" >>"$LOG"
			;;
		esac
	fi
else
	echo "$( date ) - error" >>"$LOG"
	ip address show dev eth0 >>"$LOG"
	chmod 777 "$LOG"

	/etc/init.d/networking restart
	touch "$MARKER"

	logger -s "$0:error"
	false
fi
