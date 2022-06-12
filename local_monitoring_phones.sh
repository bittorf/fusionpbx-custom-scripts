#!/bin/bash

# check via:
# tail -f /var/log/syslog

# ToDo:
# - unregistriert, aber erreichbar? -> reboot ausloesen
#   - reboot fuer flurtelefone/yealink hacken
# - pingOK, aber nicht registriert? fehler muss sichtbar sein bei counter
# - gleiche IP, aber jünger "lastseen"? drop aelteren eintrag
# - doppelte Nummern gesondert markieren
# - viele geraete fallen aus? nicht 30 sms, sondern eine gewichtige

TMPDIR='/run/shm/pbx-status'
mkdir -p "$TMPDIR"

log()
{
	local message="PID:$$ $0: $1"

	# FIXME! do '-s' not in cronmode

	logger "$message"
	echo >>'/tmp/statuspage.log.txt' "$(date ) $message"
	echo "<!-- $message -->"
}

freeswitch="/usr/local/freeswitch/bin/fs_cli"
apicommand="sofia xmlstatus profile internal reg"

echo "<html><head>"
echo "<meta http-equiv='content-type' content='text/html; charset=ISO-8859-1'>"
echo "<meta http-equiv='content-language' content='de'>"
echo "<title>EJBW.pbx</title>"
echo "<script type='text/javascript'>"
echo "<!-- stripped down version of http://kryogenix.org/code/browser/sorttable/'"

cat "/home/ejbw/sorttable.js_googleclosure"

echo "// -->"
echo "</script>"
echo "</head><body>"
echo "<small>Generiert von $0 um $( date )</small>"
echo "<table cellspacing='1' cellpadding='1' border='1' class='sortable'>"

echo "<tr>"
for OBJ in Extension Kontakt Telefon Sprache "G&uuml;ltigkeit" IPv4 Wartung NTP Umleitung Voicemail ping Uptime Fehler; do {
	echo -n "<th>$OBJ</th>"
} done
echo "</tr>"

COLOR_LIGHTGREEN="#A9F5BC"
COLOR_LIGHBLUE="#D8CEF6"
COLOR_LIGHTYELLOW="#F3E2A9"
COLOR_LIGHTRED="#F6CED8"

SCRIPT_START=$( date +%s )
SCRIPTNAME="$( basename "$0" )"

fileage_in_sec()
{
	echo $(( $(date +%s ) - $(date +%s -r "$1" || echo '0' ) ))
}

[ -f "/dev/shm/$SCRIPTNAME" ] && {
	[ $( fileage_in_sec "/dev/shm/$SCRIPTNAME" ) -gt 3600 ] && {
			rm "/dev/shm/$SCRIPTNAME"
	}
}

if [ -e "/dev/shm/$SCRIPTNAME" ]; then
	log "lockfile '/dev/shm/$SCRIPTNAME' exists: '$( cd /dev/shm/; ls -l "$SCRIPTNAME" )', abort"
	exit 0
else
	log "[OK] start"
	touch "/dev/shm/$SCRIPTNAME"
	# rm /dev/shm/pingfail_* 2>/dev/null	# see pingok()
fi

phone_timeserver()
{
	local ip="$1"
	local phone_type="$2"
	local line out

	pingok "$ip" || phone_type=

	case "$phone_type" in
		"snom821"*|"snom300"*)
			line="$( wget -qO - "http://$( pass "$phone_type" )$ip/advanced_network.htm" | fgrep 'NTP Time Server:' )"
			out="$( echo "$line" | cut -d'>' -f7 | cut -d' ' -f5 | cut -d'"' -f2 )"

			case "$out" in
				*'.'*)
					# snom821/8.7.3.19
					echo "$out"
				;;
				*)
					# snom821/8.7.4.7
					out="$( echo "$line" | cut -d'>' -f6 | cut -d' ' -f5 | cut -d'"' -f2 )"

					case "$out" in
						*'.'*)
							echo "$out"
						;;
						*)
							echo '(check)'
						;;
					esac
				;;
			esac
		;;
		*)
			echo '&mdash;'
		;;
	esac
}

phone_redirect()		# returncode = 0 -> really redirected (output = number)
{				# returncode = 1 -> no redirect (empty output) or not active (output = number)
	local ip="$1"
	local phone_type="$2"
	local number=
	local tempfile="$TMPDIR/settings_${ip}.html"

	pingok "$ip" || phone_type=

	case "$phone_type" in
		'snom821'*|'snom300'*)
			wget -qO "$tempfile" "http://$( pass "$phone_type" )$ip/settings.htm"

			number="$( fgrep 'redirect_number!: ' "$tempfile" | cut -d' ' -f2 )"

			if [ -n "$number" ]; then
				echo "$number"

				if grep -q 'redirect_event!: none' "$tempfile"; then
					return 1
				else
					return 0	# really redirected
				fi
			else
				return 1
			fi
		;;
		*)
			return 1
		;;
	esac
}

phone_uptime()
{
	local ip="$1"
	local phone_type="$2"

	pingok "$ip" || phone_type=

	case "$phone_type" in
		*"SPA112"*)
			echo "&mdash;"
		;;
		"snom821"*|"snom300"*)
			wget -qO - "http://$( pass "$phone_type" )$ip/info.htm" |
			 fgrep "Uptime:" |
			  cut -d'>' -f7 |
			   cut -d'<' -f1
		;;
		*)
			echo "&mdash;"
		;;
	esac
}

phone_voicemail_status()
{
	local extension="$1"
	local domain='172.17.0.81'	# fs_cli: eval ${domain}
	local apicommand="user_data $extension@$domain param vm-enabled"
	local status

	status="$( $freeswitch -x "$apicommand" )"

	case "$status" in
		'false')
			echo '&mdash;'
		;;
		'true')
			echo 'ok'
		;;
		*)
			echo '?'
		;;
	esac
}

phone_language()
{
	local ip="$1"
	local phone_type="$2"
	local url_pre="http://$( pass "$phone_type" )$ip"
	local url pattern

	# fixme! we must check in context:
	#  '<select size="1" name="language" tabindex=2 class="select3">

	probe()
	{
		local url="$1"
		local pattern="$2"

		case "$phone_type" in
			"snom821"*|'snom300'*)
				wget -qO - "$url" |
				 sed -n '/^.*<select size="1" name="language" .*/,/^<\/select>/p' |
				  grep -q "$pattern" || return 1
			;;
			*)
				wget -qO - "$url" | grep -q "$pattern" || return 1
			;;
		esac

		return 0
	}

	pingok "$ip" || phone_type=

	case "$phone_type" in
		"snom821"*)
			url="$url_pre/prefs.htm"
			pattern='value="Deutsch" selected'
		;;
		"snom300"*)
			url="$url_pre/prefs.htm"
			# <option value="GER" selected>Germany</option>
			pattern='value="GER" selected'

			if probe "$url" "$pattern"; then
				echo "Deutsch"
				return 0
			else
				# if only one language is available:
				pattern='<option value="GER">Germany</option>'
			fi
		;;
		"YealinkSIP-T18"*)
		;;
		"Cisco/SPA112"*)
		;;
	esac

	if [ -n "$pattern" ]; then
		if probe "$url" "$pattern"; then
			echo "Deutsch"
		else
			pattern='value="Deutsch">Deutsch</option>'

			if probe "$url" "$pattern"; then
				echo 'Deutsch2'
			else
				echo '<font color=red><b>(check)</b></font>'
			fi
		fi
	else
		echo "&nbsp;&mdash;&nbsp;"
	fi
}

phonecolor()
{
	local phone="$1"

	case "$phone" in
		"snom821"*)
			echo "$COLOR_LIGHTGREEN"
		;;
		"snom300"*)
			echo "$COLOR_LIGHBLUE"
		;;
		"YealinkSIP-T18"*)
			echo "$COLOR_LIGHTYELLOW"
		;;
		"Cisco/SPA112"*)
			echo "$COLOR_LIGHTRED"
		;;
	esac
}

pass()
{
	local phone="$1"

	case "$phone" in
		"snom821"*)
			# e.g.: username:password@
			cat USER_PASS_snom821.txt
		;;
		"snom300"*)
			cat USER_PASS_snom300.txt
		;;
		"YealinkSIP-T18"*)
			cat USER_PASS_YealinkSIP-T18.txt
		;;
		"Cisco/SPA112"*)
			cat USER_PASS_Cisco-SPA112.txt
		;;
	esac
}

reboot_link()
{
	local ip="$1"
	local phone_type="$2"
	local url_pre="http://$( pass "$phone_type" )$ip"
	local out

	case "$phone_type" in
		"snom821"*|"snom300"*)
			out="$url_pre/advanced_update.htm?reboot=Reboot"
		;;
		"YealinkSIP-T18"*)
			out="$url_pre/cgi-bin/ConfigManApp.com?Id=7"
		;;
		"Cisco/SPA112"*)
			out="$url_pre/Reboot.asp"
		;;
	esac

	[ -n "$out" ] && {
		echo "<a href='$out'>reboot</a>"
	}
}

ipcolor()
{
	local ip="$1"

	case "$ip" in
		"10.10."*)
			# wlan-netz
			echo "$COLOR_LIGHTGREEN"
		;;
		"172.17."*)
			# hausnetz J2/j4
			echo "$COLOR_LIGHBLUE"
		;;
		"192.168.0."*)
			# hausnetz reithaus
			echo "$COLOR_LIGHTYELLOW"
		;;
	esac
}

oct3()		# for sorting
{
	local ip="$1"

	case "$ip" in
		"10.10."*)
			echo "10"
		;;
		"172.17."*)
			echo "17"
		;;
		"192.168.0."*)
			echo "0"
		;;
	esac
}

pingok()
{
	local ip="$1"
	local try="${2:-6}"
	local i=0
	local error_file="/dev/shm/pingfail_$ip"

	[ -e "$error_file" ] && {
		if [ $( fileage_in_sec "$error_file" ) -gt 86400 ]; then
			rm "$error_file"
		else
			try=1
		fi
	}

	while [ $i -lt $try ]; do {
		i=$(( i + 1 ))
		ping -qc 1 "$ip" >/dev/null && {
			[ -e "$error_file" ] && rm "$error_file"
			return 0
		}

		if [ -e "$error_file" ]; then
			log "pingok() [ERR/known] ip $ip"
		else
			log "pingok() [ERR] ip $ip try: $i/$try"
		fi
	} done

	[ -e "$error_file" ] || {
		touch "$error_file"
		log "pingok() [ERR] ip $ip try: $i/$try - marked: $error_file"
	}

	return 1
}

custom_key()
{
	local name="$1"
	local out

	case "$name" in
		*"Flur/Orange"*)
			out=5
		;;
		*"Flur/Blau"*)
			out=4
		;;
		*"Flur/Gr"*)
			out=3
		;;
		*"Flur/Rot"*)
			out=2
		;;
		*"Flur/Gelb"*)
			out=1
		;;
		*"Flur/Rezeption"*)
			out=0
		;;
		*)
			out=
		;;
	esac

	[ -n "$out" ] && {
		echo -n "sorttable_customkey='$out'"
	}
}

cell_errorcount()
{
	local uniq_id="$1"
	local file="/tmp/minimoni/$uniq_id.error"
	local count lastline last_error_unixtime dummy
	local unixtime_now=$( date +%s )

	if [ -e "$file" ]; then
		count="$( wc -l <"$file" )"
		lastline="$( tail -n1 "$file" )"

		read last_error_unixtime dummy <"$file"
		case "$last_error_unixtime" in
			[0-9]*)
			;;
			*)
				last_error_unixtime=0
			;;
		esac

		if [ $(( unixtime_now - last_error_unixtime )) -gt 86400 ]; then
			echo -n "<td align='center' bgcolor='lime'><small>>24h</small></td>"
		else
			echo -n "<td align='center'>"
			echo -n "<a href='#' title='zuletzt: $lastline'>$count</td>"
	#		echo -n "</td>"
		fi
	else
		echo -n "<td align='center' bgcolor='lime'>-</td>"
	fi
}


$freeswitch -x "$apicommand" | while read LINE; do {
#	log "parse_freeswitch_output() reading: '$LINE'"

	case "$LINE" in
		# <user>141@192.168.111.21</user>
		*"<user>"*)
			EXTENSION="$( echo "$LINE" | cut -d'>' -f2 | cut -d'@' -f1 )"
			log "EXTENSION=$EXTENSION"
		;;
		# <contact>&quot;Frau Schreibeis&quot;
		*"<contact>"*)
			NAME="$( echo "$LINE" | cut -d';' -f2 | cut -d'&' -f1 )"
		;;
		# <agent>snom300/7.3.30</agent>
		*"<agent>"*)
			PHONE_TYPE="$( echo "$LINE" | cut -d'>' -f2 | cut -d'<' -f1 | sed 's/ //g' )"
		;;
		# <status>Registered(UDP)(unknown) exp(2012-12-20 14:59:38) expsecs(2405)</status>
		*"<status>"*)
			TIMEOUT="$( echo "$LINE" | cut -d'(' -f5 | cut -d')' -f1 )"
		;;
		# <network-ip>192.168.0.24</network-ip>
		*"<network-ip>"*)
			IP="$( echo "$LINE" | cut -d'>' -f2 | cut -d'<' -f1 )"
			log "IP: $IP"

			UNIQ_ID="$( echo "${EXTENSION}-${NAME}" | md5sum | cut -d' ' -f1 )"
			mkdir -p "/tmp/minimoni"

			PINGTEST=
			if pingok "$IP"; then
				PINGTEST="<small>OK</small><!-- pingok: $UNIQ_ID -->"
				echo "$IP $EXTENSION $PHONE_TYPE $NAME" >"/tmp/minimoni/$UNIQ_ID"
			else
				log "[ERROR] pingtest for IP '$IP' UNIQ_ID: $UNIQ_ID"
				PINGTEST=
				echo "$( date +%s ) $( date ) to IP '$IP'" >>"/tmp/minimoni/$UNIQ_ID.error"
			fi

			case "$TIMEOUT" in
				[0-9]*)
					# maybe send SMS?
					[ -e "/tmp/minimoni/$UNIQ_ID.sms" ] && {
						rm "/tmp/minimoni/$UNIQ_ID.sms"
					}
				;;
			esac

			REDIRECT_NUMBER=
			if REDIRECT_NUMBER="$( phone_redirect "$IP" "$PHONE_TYPE" )"; then
				# number
				:
			else
				if [ -n "$REDIRECT_NUMBER" ]; then
					REDIRECT_NUMBER="(inaktiv:$REDIRECT_NUMBER)"
				else
					REDIRECT_NUMBER='&mdash;'
				fi
			fi

#			log "parse_freeswitch_output() output stuff"
			echo "<tr>"
			echo "<td align='right' bgcolor='$( ipcolor "$IP" )' X_extension='$EXTENSION'>$EXTENSION &nbsp;</td>"
			echo "<td bgcolor='$( ipcolor "$IP" )' $( custom_key "$NAME" )>$NAME</td>"
			echo "<td bgcolor='$( phonecolor "$PHONE_TYPE" )'>$PHONE_TYPE</td>"
			echo "<td bgcolor='white' align='center'>$( phone_language "$IP" "$PHONE_TYPE" )</td>"
			echo "<td bgcolor='$( test $TIMEOUT -gt 1000 && echo 'lime' || echo 'orange' )'>$TIMEOUT sec</td>"
			echo "<!-- ip: $IP extension: $EXTENSION -->"	# needed for dial.php
			echo "<td bgcolor='$( ipcolor "$IP" )' sorttable_customkey='$( oct3 "$IP" )' X_ip='$IP'><a href='http://$( pass "$PHONE_TYPE" )$IP'>$IP</a></td>"
			echo "<td align='center'>$( reboot_link "$IP" "$PHONE_TYPE" )</td>"
			echo "<td align='center'>$( phone_timeserver "$IP" "$PHONE_TYPE" )</td>"
			echo "<td align='right'>$REDIRECT_NUMBER</td>"
			echo "<td align='center'>$( phone_voicemail_status $EXTENSION )</td>"
			echo "<td align='center' bgcolor='$( case "$PINGTEST" in *"OK"*) echo 'lime';; esac )'>${PINGTEST:-ping_failed}</td>"
			echo "<td align='center'>$( phone_uptime "$IP" "$PHONE_TYPE" )</td>"
			cell_errorcount "$UNIQ_ID"
			echo "</tr>"
		;;
		*)
#			logger -s "egal: $LINE"
		;;
	esac

#	log "parse_freeswitch_output() next"
} done >"/tmp/minimoni.html"

send_sms_and_mark()
{
	local funcname='send_sms_and_mark'
	local message="$1"
	local markfile="$2"

	local apicommand="global_getvar ALLE_MITARBEITER"
	# telefonanlage: system: variables: default: ALLE_MITARBEITER
	# ralf:0162/2666166 lars:0162/2666169 dennis:0162/2666164 willy:0162/2666065 bastian:0176/24223419
	local list_numbers="$( $freeswitch -x "$apicommand" )"

#	local number_ralf='0162/2666166'
#	local number_lars='0162/2666169'
#	local number_dennis='0162/2666164'
#	local number_willy='0162/2666065'
#	local number_bastian='0176/24223419'
#	local list_numbers="$number_lars $number_dennis $number_willy $number_bastian $number_ralf"

	local service="http://172.17.0.2/cgi-bin-tool.sh?OPT=sms"

	if [ -e "$markfile" ]; then
		touch "$markfile"
	else
		for number in $list_numbers; do {
			number="$( echo "$number" | sed 's/[^0-9]//g' )"	# only numbers
#			message="$( url_encode "$message" )"			# FIXME!
#			message="$( echo "$message" | sed 's/ /+//g' )"		# space -> +	// wget will make it
			service="$service&NUMBER=${number}&MESSAGE=${message}"
			log "$funcname() message: '$message' file: '$markfile' service: '$service'"

			wget -qO - "$service" && {
				touch "$markfile"
			}
		} done
	fi
}

its_housekeeping_time()			# maintenance
{
#	return 0			# TODO: fix the new phone

	case "$( date +%H )" in		# 00...23
		08|09|10|11|12|13|14|15|16|17|18)
			case "$( date +%w )" in
				0|6)
					# sunday|saturday
					return 1
				;;
				*)
					return 0
				;;
			esac
		;;
		*)
			return 1
		;;
	esac
}

lastseen()	# SENS: convert date of a file -> humanreadable duration, e.g.: '13 days, 5 hours, 51 minutes'
{
	local file="$1"
	local unixtime_now="$( date +%s )"
	local unixtime_file="$( stat -c "%Y" "$file")"
	local file_date="$( date -d @$unixtime_file )"
	local diff_in_sec=$(( unixtime_now - unixtime_file ))
	local output

	local border_for_sms=7200		# 2 hours
	local border_marker="$file.sms"		# will be deleted nightly by cron

	# 192.168.0.242 12 Cisco/SPA112-1.3.2(014) FAX/RH/Haustechnik
	# 172.17.1.248 105 snom300/7.3.30 Herr Wrasse
	local sms_content="$( cat "$file" )" 

	if   [ $diff_in_sec -gt $(( 86400 * 2 )) ]; then
		output=">$(( diff_in_sec / 86400 )) Tage ($file_date)"
	elif [ $diff_in_sec -gt 86400 ]; then
		output=">1 Tag ($file_date)"
	elif [ $diff_in_sec -gt 3600 ]; then
		output="ca. $(( diff_in_sec / 3600 )) Stunden"
	else
		output="$diff_in_sec sec"
	fi

	output="$( echo "$output" | sed 's/CEST//g' )"

#case "$sms_content" in
#	*'rasse'*)
#		echo >>/tmp/ZZZ "diff_in_sec: $diff_in_sec border_for_sms: $border_for_sms"
#	;;
#esac

	[ $diff_in_sec -gt $border_for_sms ] && {
		[ -e "$border_marker" ] || {
			# 192.168.0.242 12 Cisco/SPA112-1.3.2(014) FAX/RH/Haustechnik
			# 172.17.1.248 105 snom300/7.3.30 Herr Wrasse
			set -- $sms_content
#			echo >>/tmp/ZZZ "sms_content: '$sms_content'"

			local sms_ip="$1"; shift 2	# 192.168.0.242
			local sms_device="$1"; shift	# Cisco/SPA112-1.3.2(014)
			local sms_location="$1 $2 $3"	# FAX/RH/Haustechnik		// "$@" does not work?

			# sms_content: 'Herr snom300/7.3.30 172.17.1.248'
			sms_content="$sms_location $sms_device $sms_ip"
#			echo >>/tmp/ZZZ "$(date) sms_content: '$sms_content'"
			case "$sms_content" in
				*'3CXPhone'*|*'ittorf'*|*'Gast8'*|'Teamleiter'*|*'Aastra'*)
					# moving clients or 'Bittorf'
					log "ignoring special-failure: $output $sms_content"
				;;
				*)
					if its_housekeeping_time; then
						send_sms_and_mark "VoIP-Geraet unerreichbar seit $output $sms_content" "$border_marker"
						log "lastseen() send sms and mark '$border_marker'"
					else
						log "no housekeeping time: ignoring $output $sms_content"
					fi
				;;
			esac
		}
	}

	echo "$output"
}

list_ids()
{
	find /tmp/minimoni -type f ! -name '*.sms' ! -name '*.error' -exec basename {} \;
}

# for documentation:
PLAINTEXT="/tmp/phones.md" && {
	{
		echo '| Extension | IP-Adresse | Modellbezeichnung | Nutzer |'
		echo '|-----------|------------|-------------------|--------|'
	} >"$PLAINTEXT"

	true >"$PLAINTEXT.tmp"
}

#log "loop_over_uniq_ids() start"
for UNIQ_ID in $( list_ids ); do {
	# 192.168.111.130 334 snom300/7.3.30 J2-Serverraum

	read LINE 2>/dev/null <"/tmp/minimoni/$UNIQ_ID" && {
		set -- $LINE
		IP="$1"
		EXTENSION="$2"
		PHONE_TYPE="$3"
		NAME="$4$5$6"

		printf '%s\n' "|$EXTENSION|$IP|$PHONE_TYPE|$NAME|" >>"$PLAINTEXT.tmp"
	}
	
	grep -q "$UNIQ_ID" "/tmp/minimoni.html" || {
#		log "loop_over_uniq_ids() reading from /tmp/minimoni/$UNIQ_ID" 
		read LINE <"/tmp/minimoni/$UNIQ_ID"
		set -- $LINE
		IP="$1"
		EXTENSION="$2"
		PHONE_TYPE="$3"
		NAME="$4$5$6"

#		log "loop_over_uniq_ids() [ERR] not found, taking old vars: $IP / $UNIQ_ID / $LINE"

		fgrep -q "X_extension='$EXTENSION'" "/tmp/minimoni.html" && {
			fgrep -q "X_ip='$IP'" "/tmp/minimoni.html" && {
#				log "loop_over_uniq_ids() double entry: no error for '$LINE'"
				echo "<!-- double entry: no error for '$LINE' -->"
				continue
			}
		}

		echo "<tr>"
			echo "<td align='right' bgcolor='$( ipcolor "$IP" )'>$EXTENSION &nbsp;</td>"
			echo "<td bgcolor='$( ipcolor "$IP" )' $( custom_key "$NAME" )>$NAME</td>"
			echo "<td bgcolor='$( phonecolor "$PHONE_TYPE" )'>$PHONE_TYPE</td>"
			echo "<td>&nbsp;</td>"
			echo "<td> dead </td>"
			echo "<td bgcolor='$( ipcolor "$IP" )' sorttable_customkey='$( oct3 "$IP" )'><a href='http://$( pass "$PHONE_TYPE" )$IP'>$IP</a></td>"
			echo "<td align='center'>$( reboot_link "$IP" "$PHONE_TYPE" )</td>"
			echo "<td>&nbsp;</td>"		# NTP-server
			echo "<td>&nbsp;</td>"		# redirect
			echo "<td>&nbsp;</td>"		# Voicemail
			echo "<td align='center' title='UNIQID:/tmp/minimoni/$UNIQ_ID' bgcolor='red'> dead $( pingok "$IP" && echo -n 'no SIP-Registration, but Ping OK')</td>"
			echo "<td align='center' title='UNIQID:/tmp/minimoni/$UNIQ_ID'> dead, lastseen: $( lastseen "/tmp/minimoni/$UNIQ_ID" )</td>"
		echo "</tr>"
	}
} done >"/tmp/minimoni2.html"

if cat "/tmp/minimoni.html" "/tmp/minimoni2.html"; then
	log "[OK] /tmp/minimoni.html: $( ls -l /tmp/minimoni.html ) - /tmp/minimoni2.html: $( ls -l /tmp/minimoni2.html )"

	# prepare for pandoc:
	iconv -f iso-8859-1 -t UTF-8 "$PLAINTEXT.tmp" | sed 's/Ã¼/ü/' | sort -n >>"$PLAINTEXT"
	cp "$PLAINTEXT" /var/www/fusionpbx/sip-devices-table.md
else
	log "error cat"
fi

SCRIPT_READY=$( date +%s )
log "execution-time: $(( SCRIPT_READY - SCRIPT_START )) sec"

echo "</table><small><b>time for generating this overview: $(( SCRIPT_READY - SCRIPT_START )) sec</small></body></html>"

rm -f "/dev/shm/$SCRIPTNAME" || log "error rm"
log "[OK] ready"

exit 0
