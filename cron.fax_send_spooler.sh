#!/bin/sh

# tail -f /var/log/syslog
# rm /usr/local/freeswitch/storage/fax/3000/inbox/*.auth_failed

# https://api.sipgate.net/my/xmlrpcfacade
# API 1.0: http://www.sipgate.de/basic/api
# API 2.0: http://www.sipgate.de/team/faq/article/434/Was_ist_die_sipgate_API_und_welche_Funktionen_bietet_sie
# http://www.sipgate.de/static/sipgate.de/downloads/api/sipgate_API.pdf

# curl -u rossmeisl@ejbweimar.de:1975zimbo https://api.sipgate.net/my/xmlrpcfacade/samurai.BalanceGet/


LOCKFILE="/tmp/faxspooler_working"
if [ -e "$LOCKFILE" ]; then
	logger -s "lockfile '$LOCKFILE' is already there, exit"
	exit 0
else
	touch "$LOCKFILE"
fi

DIR="/usr/local/freeswitch/storage/fax/3000/inbox"

send_fax()	# api: api.sipgate.net/RPC2
{
	local extension="$1"
	local destination="$2"
	local file="$3"

	local bin_sendfax="/home/ejbw/sipgateAPI-fax.pl"
	local username password data

	case "$extension" in
		888)						# zentralfax: 03643-827111
			read -r username <"/home/ejbw/FAX-USER-888.txt"
			read -r password <"/home/ejbw/FAX-USER-888.txt"
		;;
		557)						# schulkino: 03643-862328"
			read -r username <"/home/ejbw/FAX-USER-557.txt"
			read -r password <"/home/ejbw/FAX-USER-557.txt"
		;;
		*)						# rossmeisl: 03643-827116
			read -r username <"/home/ejbw/FAX-USER-default.txt"
			read -r password <"/home/ejbw/FAX-USER-default.txt"
		;;
	esac

	# changed?
	read -r username <"/home/ejbw/FAX-USER-888.txt"
	read -r password <"/home/ejbw/FAX-USER-888.txt"

	case "$destination" in
		'0049'*)
			logger -s "number wrong0: '$destination'"
			destination="$( echo "$destination" | sed -n 's/^..\(.*\)/\1/p' )"
			logger -s "autocorrecting to: '$destination'"
		;;
	esac

	# must be E164, e.g: 4903643252696 = humanreadable: 49 03643 252696
	case "$destination" in
		'0'[1-9]*)
			destination="$( echo "$destination" | cut -b2- )"
			destination="49${destination}"
		;;
		*)
			case "${#destination}" in
				4|5|6|7)
					logger -s "number wrong1: '$destination'"
					destination="4903643${destination}"
					logger -s "autocorrecting to: '$destination'"
				;;
				1|2|3)
					logger -s "number wrong2: '$destination'"
					destination="4903643827${destination}"
					logger -s "autocorrecting to: '$destination'"
				;;
				*)
					logger -s "number is foreign country: $destination"
					destination="$( echo "$destination" | cut -b2- )"
				;;
			esac
		;;
	esac

	username="$( echo "$username" | sed 's/@/%40/g' )"
	data="'$username' '$password' '$destination' '$file'"
	local rc=0

	logger -s "$bin_sendfax $data"

	if $bin_sendfax "$username" "$password" "$destination" "$file"; then
		logger -s "[OK] for '$bin_sendfax' data: $data"
		touch "${file}.sendok"
	else
		rc=$?
		logger -s "[ERROR] rc: $rc for '$bin_sendfax' data: $data"

		case "$rc" in
			255)
				# e.g. 'Fault returned from XML RPC Server, fault code 401: Authorization Required'
				# e.g. 'Fault returned from XML RPC Server, fault code 407: Invalid parameter value.'
				# e.g. 'Fault returned from XML RPC Server, fault code 508: Format is not valid E.164.'
				# e.g. 'Fault returned from XML RPC Server, fault code 402: Internal error.'
				logger -s "[ERROR] rc: $rc / auth_failed? for '$bin_sendfax' data: $data"
				touch "${file}.auth_failed"
			;;
		esac
	fi
}

[ -d "/tmp/faxjob" ] || {
	mkdir "/tmp/faxjob"
	chmod -R 777 "/tmp/faxjob"
}

find "/tmp/faxjob" -type f -name '*.pdf' | while read FILE; do {
	logger -s "FAX: checking '$FILE', if it changes"
	HASH1="$( md5sum "$FILE" )"
	sleep 10
	HASH2="$( md5sum "$FILE" )"

	if [ "$HASH1" = "$HASH2" ]; then
		logger -s "OK: moving '$FILE' to '$DIR'"
		mv "$FILE" "$DIR"
	else
		logger -s "oops, still changing - ignoring now"
	fi
} done

find "$DIR" -type f -name '*.pdf' | while read FILE; do {
	[ -e "${FILE}.sendok" -o -e "${FILE}.faulty" -o -e "${FILE}.auth_failed" ] || {
		logger -s "waiting till file is not changed anymore: '$FILE'"
		HASH1="$( md5sum "$FILE" )"
		sleep 1					# FIXME! when age >5min, ignore
		HASH2="$( md5sum "$FILE" )"

		[ "$HASH1" = "$HASH2" ] && {
			# /usr/local/freeswitch/storage/fax/3000/inbox/557-036435448862-2013-02-03-10-28-19.pdf
			BASENAME="$( basename "$FILE" )"
			NUMBER="$( echo "$BASENAME" | cut -d'-' -f2 )"
			EXTENSION="$( echo "$BASENAME" | cut -d'-' -f1 )"

			if [ -n "$NUMBER" -a -n "$EXTENSION" ]; then
				logger -s "needs sending: from '$EXTENSION' to '$NUMBER' file: '$BASENAME'"
				send_fax "$EXTENSION" "$NUMBER" "$FILE"
			else
				logger -s "NUMBER: '$NUMBER' or EXTENSION '$EXTENSION' unfilled, ignoring - check file '$DIR/faulty/$BASENAME'"
				mkdir -p "$DIR/faulty"
				mv "$FILE" "$DIR/faulty" || rm "$FILE"	# same file
			fi
		}
	}
} done

rm "$LOCKFILE"
