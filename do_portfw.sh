#!/bin/sh

ARG1="$1"
VOIP_SERVER="${2:-172.17.0.81}"

[ -z "$ARG1" ] && {
	echo "Usage: sudo $0 <ip|stop>"
	exit 1
}

[ "$( whoami )" = "root" ] || {
	echo "sudo !!"
	exit 1
}

read FORWARDING </proc/sys/net/ipv4/ip_forward
[ "$FORWARDING" = 1 ] || {
	echo "sudo su"
	echo "echo 1 >/proc/sys/net/ipv4/ip_forward"
	echo "exit"
	exit 1
}

case "$ARG1" in
	stop)
		iptables -t nat -D PREROUTING 1
		iptables -t nat -D POSTROUTING 1 
	;;
	*)
		IP="$ARG1"

		iptables -t nat -I PREROUTING -p tcp --dport 100 -j DNAT --to-destination $IP:80
		iptables -t nat -I POSTROUTING -d $IP -j SNAT --to-source $VOIP_SERVER

		echo "use http://pubip:100 to connect to $ARG1:80"
	;;
esac
