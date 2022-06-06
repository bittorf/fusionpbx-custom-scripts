#!/bin/sh

# find / -type f -size +10M
# ...
#
# root@ejbw-pbx:/home/ejbw# du -sh /usr/local/freeswitch/log
# 17G	/usr/local/freeswitch/log

# set -x
rm -f /var/log/nginx/error.log.* /var/log/nginx/access.log.* && >/var/log/nginx/.error.log
rm -f /var/log/*.1 /var/log/*.gz

UNIXTIME_NOW="$( date +%s )"
# 2015 ... 2016 ... -> 20*
for FILE in /usr/local/freeswitch/log/freeswitch.log.20*; do {
	[ -f "$FILE" ] || continue

	case "$FILE" in
		*'.bz2'|*'.gz')
			# ignore: already compressed
			continue
		;;
	esac

#	UNIXTIME_FILE="$( date +%s -r "$FILE" )"
#	[ $(( UNIXTIME_NOW - UNIXTIME_FILE )) -gt $(( 86400 * 30 * 4 )) ] || {
#		# ignore files older than 4 months
#		continue
#	}

	ls -l "$FILE"
	bzip2 --verbose --best "$FILE"	# 10mb -> 200k
	ls -l "$FILE"*
} done

# exit 1

DEV='sda1'
set -- $( df "/dev/$DEV" | fgrep "$DEV" )
PERCENT="$( echo "$5" | cut -d'%' -f1 )"

[ $PERCENT -gt 90 ] && {
	MESSAGE="disk+full+$DEV+$PERCENT+percent+on+$HOSTNAME"
	URL="http://bwireless.mooo.com/cgi-bin-tool.sh"
	SUBJECT="Festplatte-voll-siehe-ejbx-pbx+sda1+${PERCENT}+percent+free"

	EMAIL1='bb@npl.de'
	EMAIL2='haustechnik@ejbweimar.de'
	EMAIL3='bbittorf@novomind.com'

	for EMAIL in $EMAIL1 $EMAIL2 $EMAIL3; do {
		wget -qO /dev/null "$URL?OPT=minimail&RECIPIENT=$EMAIL&SUBJECT=$SUBJECT&MESSAGE=$MESSAGE"
	} done
}


DESTDIR='/home/ejbw/backups'
mkdir -p "$DESTDIR"
TIMESTAMP="$( date +%Y%b%d_%H:%M )"

### START: sqldump ###
#

SERVER='root@intercity-vpn.de'
IP_BACKUP_SERVER='172.20.20.2'
read -r SQL_USER </home/ejbw/SQL_USER.txt
read -r SQL_PASS </home/ejbw/SQL_PASS.txt
FILE="mysqldump_${TIMESTAMP}.bin"
if mysqldump -h localhost -u $SQL_USER -p$SQL_PASS --all-databases >"$DESTDIR/$FILE"; then
	logger -s "wrote: '( ls -l "$DESTDIR/$FILE" )'"
	# initial key: ssh-copy-id -i ~/.ssh/id_rsa.pub ejbw@$IP_BACKUP_SERVER
	#
	# restore with:
	# mysql -u $SQL_USER -p$SQL_PASS <dumpfilename.sql
	scp "$DESTDIR/$FILE" ejbw@$IP_BACKUP_SERVER:/tmp/mysql_dump.sql

	# 55mb -> 7b = 15%
	bzip2 "$DESTDIR/$FILE" && FILE="$FILE.bz2"

	logger -s "wrote $DESTDIR/$FILE"

	scp "$DESTDIR/$FILE" $SERVER:/root/backup/ejbw/pbx
	logger -s "wrote backup to $SERVER:/root/backup/ejbw/pbx/$FILE"

	# CLEANUP:
	# remove backups older than 30 days / 1 months
	find "$DESTDIR" -mtime +30 -exec rm {} \;
else
	logger -s "[FATAL] writing '$FILE' to '$DIR' failed"
fi


### freeswitch.conf

FILE='/tmp/freeswitch_conf.tar'
if tar cf "$FILE" /usr/local/freeswitch/conf; then
	if scp "$FILE" ejbw@$IP_BACKUP_SERVER:/tmp; then
		logger -s "OK: scp '$FILE' to 'ejbw@$IP_BACKUP_SERVER:/tmp'"
	else
		logger -s "ERROR: scp '$FILE' to 'ejbw@$IP_BACKUP_SERVER:/tmp'"
	fi
else
	logger -s "[FATAL] writing '$FILE'"
fi
cp "$FILE" "$DESTDIR" && rm -f "$FILE"


#
### READY: sqldump ###


### START: provision-templates ###
#

DESTDIR='/home/ejbw/backups'
IP_BACKUP_SERVER='172.20.20.2'
FILE='provision-templates.tar'
tar cvf "$DESTDIR/$FILE" '/var/www/fusionpbx/includes/templates/provision'
scp "$DESTDIR/$FILE" ejbw@$IP_BACKUP_SERVER:/tmp/
rm -f "$DESTDIR/$FILE"
logger -s "wrote backup to ejbw@$IP_BACKUP_SERVER:/tmp/$FILE"

#
### READY: provision-templates ###


### START: scripts ###
#
FILE="backup_scripts_${TIMESTAMP}.tar.bz2"
tar cvjf "$DESTDIR/$FILE" \
	/var/spool/cron/crontabs/root \
	/var/www/fusionpbx/status.html \
	/usr/local/bin/cron.backup_server.sh \
	/usr/local/bin/check_incoming_calls.sh \
	/usr/local/bin/monitoring_standalone_generic.sh \
	/usr/local/bin/cron.fax_send_spooler.sh \
	/usr/local/bin/cron.freeswitch_check.sh \
	/usr/local/bin/cron.detect_role.sh \
	/usr/local/bin/invoice-calls.sh \
	/usr/local/bin/print_invoice.sh \
	/usr/local/bin/restore_mysql.sh \
	/usr/local/bin/dial.sh \
	/var/www/fusionpbx/dial.php \
	/usr/local/freeswitch/log/xml_cdr.summary \
	/home/ejbw/local_monitoring_phones.sh \
	/home/ejbw/do_portfw.sh \
	/home/ejbw/mylog.txt \
	/home/ejbw/sipgateAPI-fax.pl \
	/etc/network/interfaces \
	/etc/ppp/peers/dsl-provider \
	/etc/rc.local \
	/tmp/minimoni

# TODO: remove old backups
scp "$DESTDIR/$FILE" $SERVER:/root/backup/ejbw/pbx
logger -s "wrote backup to $SERVER:/root/backup/ejbw/pbx/$FILE"

#
### READY: scripts ###

# reschedule bad-faxes:
for FILE in /usr/local/freeswitch/storage/fax/3000/inbox/*.auth_failed; do break; done
test -f "$FILE" && {
	rm -f /usr/local/freeswitch/storage/fax/3000/inbox/*.auth_failed
}

