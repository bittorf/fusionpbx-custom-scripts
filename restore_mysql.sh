#!/bin/sh

# needs 2 minutely-cronjobs: user + root

if [ "$( id -u )" = '0' ]; then
	[ -e '/tmp/mysql_restart_needed' ] && {
		rm '/tmp/mysql_restart_needed'
		/etc/init.d/mysql restart	# see dump-import below
	}

	FILE='/tmp/freeswitch_conf.tar'
	LOCKDIR='/tmp/freewitch_conf_restore'
	[ -e "$FILE" ] && {
		tar tf "$FILE" && {
			mkdir "$LOCKDIR" && {
				if tar -C / -xvf "$FILE"; then
					logger -s "OK: $FILE"
					rm "$FILE"
				else
					logger -s "ERROR: $FILE"
				fi

				rm -fR "$LOCKDIR"
			}
		}
	}
else
	FILE='/tmp/mysql_dump.sql'
	LOCKDIR='/tmp/mysql_restore'
	read -r SQL_USER </home/ejbw/SQL_USER.txt
	read -r SQL_PASS </home/ejbw/SQL_PASS.txt

	[ -e "$FILE" ] && {
		tail -n1 "$FILE" | fgrep -q 'Dump completed on' && {
			mkdir "$LOCKDIR" && {
				if mysql -u $SQL_USER -p$SQL_PASS <"$FILE"; then	# needs ~60 secs
					touch '/tmp/mysql_restart_needed'
					logger -s "OK: $FILE"
					rm "$FILE"
				else
					logger -s "ERROR: $FILE"
				fi

				rm -fR "$LOCKDIR"
			}
		}
	}
fi

exit 0
