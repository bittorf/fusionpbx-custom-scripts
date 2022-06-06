#!/bin/sh

# PBX-2 = backup-PBX / Backupserver  = IP: 172.17.0.82/22 = hostname: 'ejbw-pbx2' - 2nd_IP: 172.20.20.2
# PBX-1 =   main-PBX / Normal-Server = IP: 172.17.0.81/22 = hostname: 'ejbw-pbx'  - 2nd_IP: 172.20.20.1

# TODO:
# - really? nameservice on PBX2 does not work when back to normal operation
# - track age of lockdir, send ONE sms if too old? or simply delete...

STORAGE='/home/ejbw'
HOSTNAME="$( hostname )"

case "$( date +%H )" in
	3|03|4|04|5|05)
		exit 0
	;;
esac

log()
{
	local message="$1"
	local option="${2:-info}"       # e.g. alert
	local file="$STORAGE/mylog.txt"

#	logger -t $0 -p daemon.$option -s "detect_role: $message"

	[ "$option" = "alert" ] && {
		echo "$( date ) $0: detect_role: $message" >>"$file"
	}
}

list_numbers()
{
	local bin="/usr/local/freeswitch/bin/fs_cli"
	local cmd="global_getvar ALLE_MITARBEITER"
	local obj

	for obj in $( "$bin" -x "$cmd" ); do {
		echo "$obj" | cut -d':' -f2
	} done | sort -u
}

sms_send()
{
	local message="$1"
	local numbers
	local service="http://172.17.0.2/cgi-bin-tool.sh?OPT=sms"

	/usr/local/freeswitch/bin/fs_cli -x "global_getvar ALLE_MITARBEITER"

	for number in $( list_numbers ); do {
		log "sms: $(date): $HOSTNAME: $number: $message" alert
		number="$( echo "$number" | sed 's/[^0-9]//g' )"        # only numbers
		service="${service}&NUMBER=${number}&MESSAGE=${HOSTNAME}+${message}+$( LC_ALL=C date +%Y%b%d_%H:%M )"

		( wget -qO - "$service" ) &
	} done 
}

check_ping()
{
	local i=10	# max tries

	case "$1" in
		'172.20.20.2')
			i=100
		;;
	esac

	while [ $i -gt 0 ]; do {
		if ping -q -c1 "$1" 2>&1 >/dev/null; then
			log "[OK] ping to $1"
			return 0
		else
			log "ping to $1 failed - try $i/10"
			i=$(( $i - 1 ))
		fi
	} done

	return 1
}

apply_network_pbx_main()
{
	if [ "$HOSTNAME" = 'ejbw-pbx2' ]; then
		local check_ip='172.20.20.2/24'
	else
		local check_ip='172.20.20.1/24'
	fi

	cat >'/etc/network/interfaces' <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet manual
	pre-up ip address add $check_ip dev eth0			# the other is .2
	pre-up ip link set dev eth0 up

auto eth1
iface eth1 inet manual
	pre-up ip address add 172.17.0.81/22 dev eth1			# the other is .82
	pre-up ip link set dev eth1 up
	up     ip route add 10.10.0.0/16 via 172.17.0.2 dev eth1	# wifi-network
	up     ip route add 192.168.0.0/24 via 172.17.0.1               # reithaus NEU via UTM
	up     ip route add 192.168.112.0/24 via 172.17.0.1		# mininet J2-dach

auto dsl-provider
iface dsl-provider inet ppp
	pre-up /sbin/ifconfig eth0 up					# line maintained by pppoeconf
	provider dsl-provider

# /etc/resolv.conf is maintained by PPPoE
EOF
}

apply_network_pbx_backup()
{
	if [ "$HOSTNAME" = 'ejbw-pbx2' ]; then
		local check_ip='172.20.20.2/24'
	else
		local check_ip='172.20.20.1/24'
	fi

	cat >'/etc/network/interfaces' <<EOF
auto lo
iface lo inet loopback

auto eth0
iface eth0 inet manual
	pre-up ip address add $check_ip dev eth0			# the other is .1
	pre-up ip link set dev eth0 up

auto eth1
iface eth1 inet manual
	pre-up ip address add 172.17.0.82/22 dev eth1			# the other is .81
	pre-up ip link set dev eth1 up
	up     ip route add 10.10.0.0/16 via 172.17.0.2 dev eth1	# wifi-network
	up     ip route add 192.168.0.0/24 via 172.17.0.1               # reithaus NEU via UTM
	up     ip route add 192.168.112.0/24 via 172.17.0.1		# mininet J2-dach

	up ip route add default via 172.17.0.1
	up echo 'nameserver 172.17.0.22' >'/etc/resolv.conf'		# special
EOF
}

apply_network()
{
	local role="$1"

	log "[START] reconfigure network to '$role'"

	[ "$role" = 'pbx_main' ] || ifdown 'dsl-provider'

#	/etc/init.d/networking stop
	apply_network_$role
#	/etc/init.d/networking start

#	if [ "$role" = 'pbx_main' ]; then
#		ifup 'dsl-provider'
#	else
#		ip address del 192.168.111.21/24 dev eth1
#	fi

	log "[READY] reconfigure network to '$1'"
}


mkdir '/tmp/LOCK-check_role' || {
	log "lock exists: /tmp/LOCK-check_role"
	exit 0
}

[ -e '/tmp/SMSTEST' ] && {
	rm '/tmp/SMSTEST'

	if [ "$HOSTNAME" = 'ejbw-pbx2' ]; then
		sms_send 'Backup-Telefonserver Test - Service OK'
	else
		sms_send 'Haupt-Telefonserver Test - Service OK'
	fi
}

if [ "$HOSTNAME" = 'ejbw-pbx2' ]; then
	# we are on 'backup-pbx'

	if [ -e "$STORAGE/DAMAGE_MODE" ]; then
		if check_ping '172.20.20.1' ; then
			rm "$STORAGE/DAMAGE_MODE"

			log "[OK] Main-PBX is up again" alert
			sms_send "Haupt-Telefonserver wieder einsatzbereit - rebooting"

			apply_network pbx_backup
			rm -fR '/tmp/LOCK-check_role'

			sleep 10	# give time for SMS/mail
			/sbin/reboot
		else
			pidof freeswitch >/dev/null || {
				log "[OK] starting up freeswitch"
				# special tweak for initfile ontop:
				# [ "$2" = 'force' ] || exit 0
				# so it will not start automatically
				/etc/init.d/freeswitch start 'force'
			}
		fi
	else
		check_ping '172.20.20.1' || {
			touch "$STORAGE/DAMAGE_MODE"

			log "[ERR] Main-PBX seems damaged" alert
			sms_send "Haupt-Telefonserver ausgefallen, Backup-System springt ein - rebooting"

			apply_network pbx_main
			rm -fR '/tmp/LOCK-check_role'

			sleep 10
			/sbin/reboot
		}
	fi
else
	# we are on 'main-PBX'
	if check_ping '172.20.20.2'; then
		[ -e "$STORAGE/PBX2_dead" ] && {
			rm "$STORAGE/PBX2_dead"

			log "[ERR] backup-PBX is up again" alert
			sms_send "Backup-Telefonserver wieder einsatzbereit"
		}
	else
		[ -e "$STORAGE/PBX2_dead" ] || {
			touch "$STORAGE/PBX2_dead"
			log "[ERR] backup-PBX seems damaged" alert
			sms_send "Backup-Telefonserver ausgefallen - bitte pruefen"
		}
	fi
fi

log "[OK] script runned"

rm -fR '/tmp/LOCK-check_role'
true
