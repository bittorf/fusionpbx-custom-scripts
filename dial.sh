#!/bin/sh

# is called from /var/www/fusionpbx/dial.php

DESTINATION="$1"	# 017624223419
EXTENSION="$2"		# 405

echo "$(date) EXTENSION=$EXTENSION DESTINATION=$DESTINATION" >>/tmp/diallog.txt

# <tr><td>404</td><td>Gast5</td><td>snom300/7.3.30</td><td>2760</td><td>192.168.111.27</td></tr>

# <!-- ip: $ip extension: $EXTENSION -->
set -- $( grep -s " extension: $EXTENSION -->"$ '/var/www/fusionpbx/status.html' )
IP="$3"

case "$IP" in
	[0-9]*)
		wget --no-check-certificate -qO /dev/null "https://root:fm1204@$IP/command.htm?number=$DESTINATION"
		echo "OK, Vorgang ausgel&ouml;st...IP: $IP"
	;;
	*)
		echo "Fehler: keine IP fuer Extension $EXTENSION gefunden.<br>"
		echo "debug: check '/usr/local/bin/dial.sh' - IP: '$IP'"
	;;
esac
