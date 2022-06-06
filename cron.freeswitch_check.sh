#!/bin/sh
# ask me everything: bittorf@bluebottle.com
#
# call it via cron every minute
# * * * * * /usr/local/bin/cron.freeswitch_check.sh 2>&1 

ARG1="$1"	# <empty> or 'debug'

log()
{
	local message="$1"
	local option="${2:-info}"	# e.g. alert
	local file="/home/ejbw/mylog.txt"

	# FIXME! do '-s' not in cronmode
	logger -t $0 -p daemon.$option "freeswitch: $message"

	[ "$option" = "alert" ] && {
		echo "$( date ) $0: freeswitch: $message" >>"$file"
	}
}

count_registrations()
{
        local bin="/usr/local/freeswitch/bin/fs_cli"
        local api_command="sofia xmlstatus profile internal reg"
        local pattern="</registration>"
        local out

        out="$( $bin -x "$api_command" | fgrep "$pattern" | wc -l )"
        out="$( echo "$out" | sed 's/[^0-9]//g' )"

	echo ${out:-0}
}

sipgate_regs_normal()
{
        local bin="/usr/local/freeswitch/bin/fs_cli"
        local api_command="sofia xmlstatus"
        local pattern="sipconnect.sipgate.de"
        local out normal=2	# 2021-jul27 | testblock rausgenommen, war:3 nun: 2

        out="$( $bin -x "$api_command" | grep -c "$pattern" )"

	test $out -eq $normal
}


#[ -e '/tmp/BLA' ] && {
#	touch /tmp/ZWANGSTRENNUNG
#	/sbin/ifdown dsl-provider
#	sleep 180
#	/sbin/ifup dsl-provider
#	sleep 60
#	/usr/local/bin/monitoring_standalone_generic.sh
#	sleep 120
#	mv /tmp/ZWANGSTRENNUNG /tmp/ZWANGSTRENNUNG.alt
#
#	rm -f '/tmp/BLA'
#	exit 0
#}

db_reinit()
{
	# 2021-07-27 06:03:02.023120 [ERR] switch_core_sqldb.c:526 SQL ERR [database disk image is malformed]
	grep "database disk image is malformed" /usr/local/freeswitch/log/freeswitch.log || return 0
	log "[ERR] found db-errors in log, doing db_reinit"

	cd /usr/local/freeswitch/db
	mv core.db         "core.dn-kaputt-$(date +%s)"
	mv core.db-journal "core.db-journal-kaputt-$(date +%s)"
	cd -
}

if [ "$ARG1" = 'debug' ]; then
	set -x
	count_registrations
	echo
	sipgate_regs_normal
	exit $?
else
	COUNT=$( count_registrations )
fi

if [ $COUNT -eq 0 ]; then
	ip link show dev 'eth1' | grep -q "state UP" || {
		log "[ERR] restarting eth1"
		ip link set dev eth1 up
#		ifconfig eth1 up
#		# FIXME! duplated '/etc/network/interfaces'
#		ip route add 10.10.0.0/16 via 172.17.0.2 dev eth1
#		ip route add 192.168.0.0/24 via 172.17.0.1
#		ip route add 192.168.112.0/24 via 172.17.0.1
	}

	printf '%s' '#' >>/tmp/DB_BAD
	read DBCOUNT </tmp/DB_BAD
	[ ${#DBCOUNT} -ge 7 ] && db_reinit

	if [ -e '/tmp/ZWANGSTRENNUNG' ]; then
		log "[OK] only $COUNT regs, pid: '$( pidof freeswitch )' - but '/tmp/ZWANGSTRENNUNG' is there"
	else
		log "[ERR] needs a restart: $COUNT regs, pid: '$( pidof freeswitch )' - no '/tmp/ZWANGSTRENNUNG' found" alert
		/etc/init.d/freeswitch restart
		log "restarted, pid: '$( pidof freeswitch )'"
	fi
else
	>/tmp/DB_BAD
	log "[OK] count: $COUNT regs"
fi

if sipgate_regs_normal; then
	:
else
	log "[ERR] needs a restart : sipgate_regs_normal()"
	/etc/init.d/freeswitch restart
	log "restarted, pid: '$( pidof freeswitch )'"
fi

set -- $( ip route list exact 0.0.0.0/0 ); GATEWAY=$3
#GATEWAY="$( ip address show dev ppp0 | fgrep "inet " | while read LINE; do set -- $LINE; echo $2; done )"

#
### REMOVE!
# read GATEWAY </tmp/GW
###
#

[ -e /tmp/GW ] && read GATEWAY_OLD </tmp/GW
[ "${GATEWAY_OLD:-$GATEWAY}" = "$GATEWAY" ] || {
	log "IP changed: '$GATEWAY_OLD' -> '$GATEWAY'" alert
}

exit 0

if [ -z "$GATEWAY" ]; then
	[ -e '/tmp/NO_GATEWAY' ] || {
		# reroute to 'ipfire', will be rewritten if inet is ok again
		ip route add default via 192.168.111.1 metric 2		# ipfire
		echo >'/etc/resolv.conf' 'nameserver 8.8.8.8'

		touch '/tmp/NO_GATEWAY'
		log "[ERR] no gateway - no internet" alert
	}
else
	[ -e '/tmp/NO_GATEWAY' ] && {
		rm '/tmp/NO_GATEWAY'
		log "[OK] gateway found" alert
	}
fi

echo "$GATEWAY" >/tmp/GW

pidof pppd >/dev/null || {
	/sbin/ifdown dsl-provider
	sleep 30
	/sbin/ifup dsl-provider
	log "[OK] ppp daemon restarted - pid now '$( pidof pppd )'"
}

exit 0
