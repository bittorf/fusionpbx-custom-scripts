#!/bin/sh

MONTH_SHORT="$(  date +%b )"    # Dec
DAY_OF_MONTH="$( date +%d )"    # 01...31
YEAR="$(         date +%Y )"    # 2013

DIR="/usr/local/freeswitch/log/xml_cdr/archive"
DIR="$DIR/$YEAR/$MONTH_SHORT/$DAY_OF_MONTH"
SMS_ARCHIV="/tmp/sms_archiv"	# remove each day or move to .old

# logger -s "$0: DIR: '$DIR'"

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

	local number
	local service="http://172.17.0.2/cgi-bin-tool.sh?OPT=sms"

	for number in $( list_numbers ); do {
		number="$( echo "$number" | sed 's/[^0-9]//g' )"        # only numbers
		service="$service&NUMBER=${number}&MESSAGE=${message}"
		logger -s "send_sms_and_mark() message: '$message' file: '$markfile' service: '$service'"

		if wget -qO - "$service"; then
			echo "$(date) OK sms an $number geschickt" >>"$SMS_ARCHIV"
		else
			echo "$(date) fail: $service" >>"$SMS_ARCHIV"
		fi
	} done
}

is_watched_number()
{
	local number_kurt='493643805123'
	local number_tommek='493643827501'		# FIXME!
	local number_reithaus_sammelstoerung='588'

	# disabled: 2020-nov-27
	number_reithaus_sammelstoerung=

	for NUMBER in $number_reithaus_sammelstoerung 558 559 700 $number_kurt $number_tommek; do {
		grep -q "<destination_number>$NUMBER</destination_number>" "$FILE" && return 0
	} done

	return 1
}

for FILE in $DIR/*; do {
	is_watched_number && {
#		logger -s "is_watched_number: yes: $NUMBER"

		grep -qs "$FILE" "$SMS_ARCHIV" || {
			# mark as already done
			echo "$(date) $FILE" >>"$SMS_ARCHIV"

			# <caller_id_number>04917624223419</caller_id_number>
			# <destination_number>558</destination_number>
			FROM="$( grep '</caller_id_number>' "$FILE" | tail -n1 | cut -d'>' -f2 | cut -d'<' -f1 )"

			is_valid_action()
			{
				case "$FROM" in
					'01930100'|'anonymous')
						# Telekom SMS-Zentrale
						return 1
					;;
				esac

				FORCE_GROUP=
				# var is build in is_watched_number()
				case "$NUMBER" in
					'493643805123')
						FORCE_GROUP='kurt'
						return 0
					;;
					'493643827501')
						FORCE_GROUP='tommek'
						return 0
					;;
					'588')
						# reithaus sammelstoerung
						FORCE_GROUP='ejbw'
						return 0
					;;
				esac

				test ${#FROM} -gt 3 && return 0

				return 1
			}

			if is_valid_action; then
				logger -s "send sms: from $FROM to $NUMBER - file: $FILE FORCE_GROUP: '$FORCE_GROUP'"

				case "$NUMBER" in 559) ORIGINATOR="Servicenummer MarinaBH" ;; esac

				[ "$NUMBER" = '558' ] && {
					PRE="493643827"

					if   grep -q "destination_number>${PRE}551</destination_number>" "$FILE"; then
						ORIGINATOR="Servicenummer Dorfhotel Fleesensee"
					elif grep -q "destination_number>${PRE}554</destination_number>" "$FILE"; then
						ORIGINATOR="Servicenummer IBO Fleesensee"
					elif grep -q "destination_number>${PRE}558</destination_number>" "$FILE"; then
						ORIGINATOR="Servicenummer Boltenhagen"
						case "$FROM" in
							*'039932470'*)
								ORIGINATOR="$ORIGINATOR/ibfleesensee"
							;;
						esac
					else
						ORIGINATOR="Unknown Originator"
					fi
				}

				[ "$NUMBER" = '700' ] && ORIGINATOR="Buero Zentrale"
				[ "$NUMBER" = '588' ] && ORIGINATOR="Reithaus Sammelstoerung"

				grep -sq "# $( date +%Y%b%d ) - $FROM" "$SMS_ARCHIV" || {
					echo "# $( date +%Y%b%d ) - $FROM" >>"$SMS_ARCHIV"
					sms_send "Anruf $ORIGINATOR/$NUMBER von $FROM" $FORCE_GROUP
				}
			else
				logger -s "ignoring, from: '$FROM'"
			fi
		}
	}
} done
