#!/bin/sh

EXTENSION="$1"		# 333 or "333 102"
START_MONTH_NUMBER="$2"	# 12
START_DAY_OF_MONTH="$3"	# 01
START_YEAR="$4"		# 2013
END_MONTH_NUMBER="$5"	# 12
END_DAY_OF_MONTH="$6"	# 30
END_YEAR="$7"		# 2013
FILE='/usr/local/freeswitch/log/xml_cdr.summary'
FILE_ANALYSIS="/tmp/call_summary.$$"
SUM_PRICE=0
SUM_DURATION=0
SUM_CALLS=0

# echo "$0: args: $@" >/tmp/BLA

log()
{
	logger -s "$0: $1"
}

selectbox()
{
	local subject="$1"
	local var="$2"
	local list="$3"
	local now="$4"
	local object on

	echo "$subject: <select name='$var'>"
	for object in $list; do {
		test ${#object} -eq 1 && object="0$object"
		on=
		test "$object" = "$now" && on='selected'
		echo "<option $on>$object</option>"
	} done
	echo "</select>"
}

html_show_form()
{
	local MONTH DAY YEAR now on
	local bgcolor='#C0FDB8'		# lightgreen

	echo "<html><head><title>Eingabe</title></head><body bgcolor='$bgcolor'>"
	echo "<table cellspacing='10' cellpadding='0' border='0'><tr>"
	echo "<td><img src='logo_ejbweimar.gif'></td>"
	echo "<td valign='bottom'><h1>EJB Weimar - Auswertung Telefonanlage</h1></td>"
	echo "</tr></table>"
	echo "<h3>Bitte die Suche eingrenzen:</h3>"

	echo "<form action='' method='get'>"
	echo "Telefon/Anschlu&szlig: <input name='EXTENSION' value='110' type='text' maxlength='30'>"
	echo "<br><i>Hinweis:</i>"
	echo "<br>&bullet;&nbsp;mehrere Nummern durch Leerzeichen trennen:"
	echo "<br>&nbsp;&nbsp;&bullet;&nbsp;z.b. alle Flurtelefone: 200 220 240 260 270 271 300"
	echo "<br>&nbsp;&nbsp;&bullet;&nbsp;z.b. Projekt Schulkinowoche: 10 14 15 16 33 34"
	echo "<br>&bullet;&nbsp;leerlassen bedeutet ALLE Anschl&uuml;sse auswerten.<br>"

	echo "<br>Beginn der Auswertung:"
	selectbox 'Tag'   'START_DAY_OF_MONTH' "$(seq 31 -1 1)"             "$(date +%d)"
	selectbox 'Monat' 'START_MONTH_NUMBER' "$(seq 12 -1 1)"             "$(date +%m)"
	selectbox 'Jahr'  'START_YEAR'         "$(seq $(date +%Y) -1 2012)" "$(date +%Y)"

	echo "<br>Ende der Auswertung:"
	selectbox 'Tag'     'END_DAY_OF_MONTH' "$(seq 31 -1 1)"             "$(date +%d)"
	selectbox 'Monat'   'END_MONTH_NUMBER' "$(seq 12 -1 1)"             "$(date +%m)"
	selectbox 'Jahr'    'END_YEAR'         "$(seq $(date +%Y) -1 2012)" "$(date +%Y)"

	echo "<br><br><input type='submit' value='Auswertung starten'>"

	echo "</form>"
	echo "</body></html>"
}

  if [ "$EXTENSION" = "show_form" ]; then
	html_show_form
	exit 0
elif [ -z "$2" ]; then
	log "Usage: $0 '<empty> or EXT1 EXT2 ...' <START-MONTH_NUMBER> <START-DAY_OF_MONTH> <START-YEAR> <END-MONTH_NUMBER> <END-DAY_OF_MONTH> <END-YEAR>"
	log "e.g. : $0 01 06 2013 01 30 2013"

	exit 0
else
	HOUR=00; MIN=00; SEC=00
	WISH_EPOCH_START="$( date --date "${START_YEAR}-${START_MONTH_NUMBER}-${START_DAY_OF_MONTH} ${HOUR}:${MIN}:${SEC}" +%s )"
	WISH_EPOCH_END="$( date --date "${END_YEAR}-${END_MONTH_NUMBER}-${END_DAY_OF_MONTH} ${HOUR}:${MIN}:${SEC}" +%s )"

	log "START: $WISH_EPOCH_START"
	log "END: $WISH_EPOCH_END"
fi

# typical line:
# FROM='107'; TO='03615596403'; DURATION='189'; START_EPOCH='1370497641'; BASIC_PRICE='100'; EINHEITEN='4'; PRICE_OVERALL='400'; DAY_OF_MONTH='06'; YEAR='2013'; DAY_OF_WEEK='4'; MONTH_NUMBER='06'
#

while read LINE; do {
	eval $LINE
	test $START_EPOCH -ge $WISH_EPOCH_START -a $START_EPOCH -lt $WISH_EPOCH_END || continue

	if [ -z "$EXTENSION" ]; then
		echo "A=$START_EPOCH; $LINE"
	else
		for EXT in $EXTENSION; do {
			case " $FROM " in
				*" $EXT "*)
					echo "A=$START_EPOCH; $LINE"
				;;
			esac
		} done
	fi
} done <"$FILE" | sort >"$FILE_ANALYSIS"
touch "$FILE_ANALYSIS"

seconds_humanreadable()
{
	local integer="$1"
	local humanreadable min sec hours days

	min=$(( $integer / 60 ))
	sec=$(( $integer % 60 ))

	if   [ $min -gt 1440 ]; then
		days=$(( $min / 1440 ))
		min=$(( $min % 1440 ))
		hours=$(( $min / 60 ))
		min=$(( $min % 60 ))
		humanreadable="${days}d ${hours}h ${min}min ${sec}sec"
	elif [ $min -gt 60 ]; then
		hours=$(( $min / 60 ))
		min=$(( $min % 60 ))
		humanreadable="${hours}h ${min}min ${sec}sec"
	elif [ $min -gt 0 ]; then
		humanreadable="${min}min ${sec}sec"
	else
		humanreadable="${sec}sec"
	fi

	echo "$humanreadable"
}

price_humanreadable()
{
	local value="$1"
	local length euro cent

	if [ $value -gt 10000 ]; then
		euro=$(( $value / 10000 ))
		cent=$(( $value % 10000 ))

		echo "${euro}.$( echo "$cent" | cut -b1,2 ) Euro"
	else
		echo "$(( $value / 100 )) ct"
	fi
}

# prepare summary
while read LINE; do {
	eval $LINE
	SUM_CALLS=$(( $SUM_CALLS + 1 ))
	SUM_PRICE=$(( $SUM_PRICE + $PRICE_OVERALL ))
	SUM_DURATION=$(( $SUM_DURATION + $DURATION ))
} done <"$FILE_ANALYSIS"

html_callsummary()
{
	local tax='19'						# 19% Umsatzsteuer
	local taxes=$(( ($SUM_PRICE * $tax) / 1$tax ))
	local without_taxes=$(( $SUM_PRICE - $taxes ))

	echo "<p><b>"
	echo "<br>Zeitraum: ${START_YEAR}-${START_MONTH_NUMBER}-${START_DAY_OF_MONTH} bis ${END_YEAR}-${END_MONTH_NUMBER}-${END_DAY_OF_MONTH}"
	echo "<br>Summe Anrufe: $SUM_CALLS"
	echo "<br>Summe Geb&uuml;hren: $( price_humanreadable "$SUM_PRICE" ) (inkl. $tax% Umsatzsteuer)"
	echo "<br>Summe Geb&uuml;hren: $( price_humanreadable "$without_taxes" ) (ohne Umsatzsteuer)"
	echo "<br>enthaltene Umsatzsteuer: $( price_humanreadable "$taxes" )"
	echo "<br>Summe Gespr&auml;chszeit: $( seconds_humanreadable "$SUM_DURATION" )"
	echo "</b></p>"
}

html_head()
{
	local bgcolor='#C0FDB8'		# lightgreen

	echo "<html><head><title>EJB Weimar Telefonrechnung</title></head><body bgcolor='$bgcolor'>"

	echo "<table cellspacing='10' cellpadding='0' border='0'><tr>"
	echo "<td><img src='logo_ejbweimar.gif'></td>"
	echo "<td valign='bottom'><h1>EJB Weimar - Auswertung Telefonanlage</h1></td>"
	echo "</tr></table>"


#	echo "<h1>EJB Weimar - Auswertung Telefonanlage</h1>"
	echo "<h3>Aufstellung Telefonkosten f&uuml;r die Anschl&uuml;sse: ${EXTENSION:-alle}</h3>"
	html_callsummary
}

html_table()
{
	echo "<table cellspacing='0' cellpadding='0' border='1'>"
	echo "<tr><th>Zeitpunkt</th><th>Anschlu&szlig;</th><th>Ziel</th><th>Dauer</th><th>Einheiten</th><th>Kosten</th></tr>"

	while read LINE; do {
		eval $LINE
		echo "<tr><td>$( date -d @${START_EPOCH} )</td><td align='center'>$FROM</td><td>$TO</td><td align='right'>$( seconds_humanreadable "$DURATION" )</td><td align='right'>$EINHEITEN</td><td align='right'>$( price_humanreadable "$PRICE_OVERALL" )</td></tr>"
	} done <"$FILE_ANALYSIS"

	echo "</table>"
}

html_tail()
{
	html_callsummary
	echo "</body></html>"
}

html_head
html_table
html_tail

rm "$FILE_ANALYSIS"
