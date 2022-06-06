#!/bin/sh

TEMP="/tmp/html.$$"
BIN='/home/ejbw/local_monitoring_phones.sh'

[ -n "$( ls -l '/tmp/html.'* 2>/dev/null )" ] && exit 0

if $BIN >"$TEMP"; then
#	logger -s "OK"

	mv "$TEMP" '/var/www/fusionpbx/status.html'
	chmod 777  '/var/www/fusionpbx/status.html'
	scp /var/www/fusionpbx/status.html root@intercity-vpn.de:/var/www/networks/ejbw-pbx/moni.html
else
	logger -s "[ERR] '$BIN' returned $?"
	rm -f "$TEMP"
fi
