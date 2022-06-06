#!/bin/bash
#
# use a cronjob like this:
# */15 * * * * /usr/local/bin/monitoring.sh

#logger -s "$0: [START]"

NETWORK="ejbw"
HARDWARE="AtomD560"
ETHERNET="eth0"

# special
ETHERNET_PHY="eth0"
WANTYPE="pppoe"

MYGW="$( ip route list exact 0.0.0.0/0 | cut -d' ' -f3 )"
[ -z "$MYGW" ] && exit 0

set -- $( df --block-size=MB | grep ^'/dev/sda1' )
STORAGE="flash.free.kb%3a${4}"
# MYDEV="$( ip route list exact 0.0.0.0/0 | head -n1 | cut -d' ' -f5 )"
MYDEV="$( set -- $( ip route list exact '0.0.0.0/0' ); while shift; do test "$1" = 'dev' && break; done; echo $2 )"
MYIP="$( ip address show dev $MYDEV | sed -n "s/^.*inet \(.*\)\/.*/\1/p" )"
URL="http://intercity-vpn.de/networks/$NETWORK/meshrdf"
MYPUBIP="$( wget -qO - "http://intercity-vpn.de/scripts/getip/" )"
read HOSTNAME </proc/sys/kernel/hostname
HOSTNAME="J2-$HOSTNAME"
VERSION=$(( $( stat --printf %Y /var/lib/dpkg/status ) / 3600 ))
while read L; do case "$L" in MemTotal:*) set -- $L; RAM=$2; break;; esac; done </proc/meminfo
MAC="$( ip link show dev "$ETHERNET_PHY" | sed -n "s|^.*link/ether \([a-f0-9:]*\).*|\1|p" )"
MAC="${MAC//:/}"
UPTIME=$(( $( read A </proc/uptime; echo ${A%%.*} ) / 3600 ))
SVN="$( cd /var/www/fusionpbx; svn info | grep ^'Revision: ' | cut -d' ' -f2 )"
read LOAD </proc/loadavg; LOAD=${LOAD%% *}; LOAD=${LOAD//./}
SSID=

[ -e "/usr/local/bin/omap4_temp" ] && {
	SSID="$( /usr/local/bin/omap4_temp )"
	SSID="$SSID+%c2%b0C"	# space grad celcius
}

[ -e "/usr/bin/scrot" ] && {		# comment out, if unneeded
	HASH_OLD="$( sha1sum "/tmp/screenshot.jpg" )"
	export DISPLAY=:0
	scrot --quality 10 "/tmp/screenshot.jpg"
	HASH_NEW="$( sha1sum "/tmp/screenshot.jpg" )"

	if [ "$HASH_OLD" = "$HASH_NEW" ]; then
		logger -s "screen didnt change"
	else
		logger -s "screen changed, sending screenshot"
		scp "/tmp/screenshot.jpg" root@intercity-vpn.de:/var/www/networks/$NETWORK/settings/$MAC.screenshot.jpg
	fi
}

SWITCH="$( [ -e "/sbin/mii-tool" ] && /sbin/mii-tool 2>/dev/null "$ETHERNET_PHY" )"
case "$SWITCH" in
	*'100baseTx-FD'*) SWITCH="B" ;;
	*'1000baseT-HD'*) SWITCH="c" ;;
	*'1000baseT-FD'*) SWITCH='C' ;;
	*) SWITCH="-" ;;
esac

#logger -s "SWITCH: '$SWITCH'"

URL="$URL/?local=$( date +%Y%b%d_%Huhr%M )&node=0&city=168&mac=${MAC}&latlon=&hostname=${HOSTNAME}&update=0&wifidrv=&olsrver=&t3=etx_ffeth&olsrrestartcount=0&olsrrestarttime=&portfw=&optimizenlq=&optimizeneigh=off&txpwr=0&wifimode=ap&channel=1&mrate=auto&hw=${HARDWARE}&frag=&rts=&pfilter=&gmodeprot=0&gmode=11ng&profile=${NETWORK}_ap&noise=-1&rssi=&distance=&version=${VERSION}&reboot=1&up=${UPTIME}&load=${LOAD}&forwarded=0&essid=${SSID}&bssid=&gw=1&gwnode=1&etx2gw=1&hop2gw=0&neigh=&users=&pubip=${MYPUBIP}&sens=&wifiscan=&v1=$( uname -r )&v2=${SVN}&s1=${SWITCH}&h1=${RAM}&h2=&h4=2&h5=33&h6=4096&h7=337&d0=&d1=&n0=&i0=${WANTYPE}&i1=wan&i2=${MYIP}%2f29&i3=2048&i4=128&i5=${MYGW}&r0=&w0=wlan0&w1=0&services=$STORAGE"

#logger -s "$0: ${#URL} bytes: $URL"
if wget -qO /dev/null "$URL"; then
	touch /tmp/MONITORING.ok
else
	touch /tmp/MONITORING.err
fi

#logger -s "$0: [READY]"

