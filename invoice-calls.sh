#!/bin/sh

# Idee:
# jeden tag 1mal durchlaufen lassen (mitte und am ende des tages)
# und in ein file schreiben, z.b.
# /usr/local/freeswitch/log/xml_cdr.summary
#
# all days:
# find "$DIR" -type d | grep "/[0-9][0-9]"$
#
# call this script:
# DIR="/usr/local/freeswitch/log/xml_cdr/archive"
# find "$DIR" -type d | grep "/[0-9][0-9]"$ | while read LINE; do oldIFS="IFS"; IFS='/'; set -- $LINE; IFS="$oldIFS"; ./invoice-calls.sh "$9" "${10}" "$8"; done
#
# sample query:
# SUM=0; grep ^"FROM='332'" /usr/local/freeswitch/log/xml_cdr.summary | grep "'2013'" | while read LINE; do eval $LINE; SUM=$(( ${SUM:-0} + $PRICE_OVERALL )); echo $SUM; done
#
# FILTER_EXTENSION="$1"		# e.g. 102 will only work on files where this extension is involved

log()
{
	logger -s "$0: $1"
}

if [ -z "$1" ]; then
	MONTH_SHORT="$(  date +%b )"	# Dec
	DAY_OF_MONTH="$( date +%d )"	# 01...31
	YEAR="$(         date +%Y )"	# 2013

	log "[OK] using call: $0 '$MONTH_SHORT' '$DAY_OF_MONTH' '$YEAR'"
else
	MONTH_SHORT="$1"
	DAY_OF_MONTH="$2"
	YEAR="$3"
fi

SUMMARY='/usr/local/freeswitch/log/xml_cdr.summary'
DIR="/usr/local/freeswitch/log/xml_cdr/archive"  # /2013/Dec/31
DIR="$DIR/$YEAR/$MONTH_SHORT/$DAY_OF_MONTH"

SUM=0

[ -d "$DIR" ] || {
	log "dir does not exist: '$DIR' (no calls where made)"
	exit 0
}

extract_tag()
{
	echo "$1" | cut -d'>' -f2 | cut -d'<' -f1
}

price_humanreadable()
{
	local value="$1"
	local length euro cent

	# 100 -> 1 ct
	# 1000 -> 10 ct
	# 10000 -> 1 Euro
	# 10500 -> 1.05 Euro
	# 10590 -> 1.06 Euro
	# 15100 -> 1.51 Euro

	if [ $value -gt 10000 ]; then
		euro=$(( $value / 10000 ))
		cent=$(( $value % 10000 ))

		echo "${euro}.$( echo "$cent" | cut -b1,2 ) Euro"
	else
		echo "$value ct/100"
	fi
}

number2price()
{
	local number="$1"
	local de_mobile='1300'	# ct/min * 100
	local o

	# API: http://www.sipgate.de/beta/public/static/downloads/basic/api/sipgate_api_documentation.pdf
	# HUMAN: http://www.sipgate.de/trunking/tarife
	# inklusive 19% Umsatzsteuer

	# todo:
	# VoIP zu anderen ist kostenlos, wie detektieren?
	# 

	case "$number" in
		'30003'*)
			# fax: sipgate plus: http://www.sipgate.de/basic/produkte
			log "fax: $number"
			number="$( echo "$number" | cut -b6- )"
			log "nummer nun: $number"
		;;
	esac

	case "$number" in
		# http://de.wikipedia.org/wiki/Deutscher_Mobilfunkmarkt#Vorwahlen
		# Telekom:
		'01511'*|'01512'*|'01514'*|'01515'*|'01516'*|'01517'*|'0160'*|'0170'*|'0171'*|'0175'*)
			o="$de_mobile"
		;;
		# Vodafone:
		'01520'*|'01522'*|'01523'*|'01525'*|'01526'*|'0162'*|'0172'*|'0173'*|'0174'*|'01529'*|'01521'*)
			o="$de_mobile"
		;;
		# E-Plus:
		'01573'*|'01575'*|'01577'*|'01578'*|'0163'*|'0177'*|'0178'*|'01570'*|'01579'*)
			o="$de_mobile"
		;;
		# O2:
		'01590'*|'0176'*|'0179'*)
			o="$de_mobile"
		;;
		# Sonderrufnummern:
		'01801')
			# kostenlos, wenn andere Seite auch Sipgate-Teilnehmer
			o='400'
		;;
		'01802')
			o='overall 600'	# 6 ct/Verbindung
		;;
		'01803')
			o='900'
		;;
		'01804')
			o='2000'
		;;
		'01805')
			o='1400'
		;;
		'01806')
			o='overall 2000'
		;;
		'01888')
			o='600'
		;;
		'0700')
			o='1200'
		;;
		'0800')
			o='000'
		;;
		'0900')
			# nicht moeglich, ebenso: 0137, 0138, 01212, 0185, 0181, 0188, 032, + 118xx
			o='36000'
		;;
		'115')
			o='700'
		;;
		# Deutschland Festnetz
		'01'*|'02'*|'03'*|'04'*|'05'*|'06'*|'07'*|'08'*|'09'*)
			o='100'
		;;
		# Ausland:
		'00'*)
			log "ausland"
			case "$number" in
				'0043')
					# oesterreich
					o='240'		# handy='14.9'
				;;
				*)
					o='1000'
				;;
			esac
		;;
		*)
			if [ ${#number} -le 6 ]; then
				# Deutschland Festnetz
				o='100'
			else
				log "nummer $number - preis nicht bestimmbar"
			fi
		;;
	esac

	echo "$o"
}

# for FILE in $DIR/*; do {
for FILE in $( ls -1t $DIR ); do {
	FILE="$DIR/$FILE"
	[ -e "$FILE" ] || break
#	log "processing '$FILE'"

	while read LINE; do {
		case "$LINE" in
			*'<sip_from_user>'*)
				SIP_FROM_USER="$( extract_tag "$LINE" )"	# e.g. 32
			;;
			*'<direction>'*)
				DIRECTION="$( extract_tag "$LINE" )"		# e.g. inbound
			;;
			*'<sip_to_user>'*)
				SIP_TO_USER="$( extract_tag "$LINE" )"		# e.g. 03643827112
			;;
			*'<hangup_cause>'*)
				HANGUP_CAUSE="$( extract_tag "$LINE" )"		# e.g. NORMAL_CLEARING
			;;
			*'<start_epoch>'*)
				START_EPOCH="$( extract_tag "$LINE" )"		# e.g. 1387462451
				START_TIME="$( date -d @${START_EPOCH} )"	# e.g. Thu Dec 19 10:56:31 CET 2013
			;;
			*'<billsec>'*)
				BILL_SEC="$( extract_tag "$LINE" )"		# e.g. 120
			;;
		esac
	} done <"$FILE"

	[ ${#SIP_FROM_USER} -le 4 -a ${#SIP_TO_USER} -le 4 ] && DIRECTION='internal'
	[ ${#SIP_FROM_USER} -le 4 -a ${#SIP_TO_USER} -gt 4 ] && DIRECTION='outbound'

	case "$DIRECTION" in
		'internal'|'inbound')
			continue
		;;
		*)
			# is a number? can be e.g. '1545163t0'
			test "$SIP_FROM_USER" -eq "$SIP_FROM_USER" 2>/dev/null || continue

			[ "$BILL_SEC" -eq 0 ] && continue

#			[ -n "$FILTER_EXTENSION" ] && {
#				[ "$FILTER_EXTENSION" = "$SIP_FROM_USER" ] || continue
#			}
		;;
	esac

	# API: http://www.sipgate.de/beta/public/static/downloads/basic/api/sipgate_api_documentation.pdf
	# HUMAN: http://www.sipgate.de/trunking/tarife

	# todo:
	# VoIP zu anderen ist kostenlos, wie detektieren?
	# 

	PRICE="$( number2price "$SIP_TO_USER" )"	# can be 'overall: 600' or '600'
	EINHEITEN=$(( $BILL_SEC / 60 ))
	[ $(( $BILL_SEC % 60 )) -eq 0 ] || EINHEITEN=$(( $EINHEITEN + 1 ))
	PRICE_OVERALL=$(( $EINHEITEN * $PRICE ))
	SUM=$(( $SUM + $PRICE_OVERALL ))

	DAY_OF_WEEK="$(  date -d @$START_EPOCH +%u )"	# e.g.  1 = Monday
	MONTH_NUMBER="$( date -d @$START_EPOCH +%m )"	# e.g. 12 = December

	echo "FROM: $SIP_FROM_USER -> $SIP_TO_USER ($DIRECTION), $BILL_SEC sec at $START_TIME -> $HANGUP_CAUSE ($PRICE ct/min = $PRICE_OVERALL)"
	OUT="FROM='$SIP_FROM_USER'; TO='$SIP_TO_USER'; DURATION='$BILL_SEC'; START_EPOCH='$START_EPOCH'; BASIC_PRICE='$PRICE'; EINHEITEN='$EINHEITEN'; PRICE_OVERALL='$PRICE_OVERALL'; DAY_OF_MONTH='$DAY_OF_MONTH'; YEAR='$YEAR'; DAY_OF_WEEK='$DAY_OF_WEEK'; MONTH_NUMBER='$MONTH_NUMBER'"
	grep -q ^"$OUT"$ "$SUMMARY" || {
		logger -s "rein: $OUT"
		echo "$OUT" >>"$SUMMARY"
	}
} done

log "Summe: $SUM - humanreadable: $( price_humanreadable "$SUM" ) - wrote to '$SUMMARY'"
