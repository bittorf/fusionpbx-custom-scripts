#!/bin/sh

list_phonenumbers()
{
	local freeswitch apicommand list_numbers file number

	file='/tmp/phonenumber_cache'
	freeswitch="/usr/local/freeswitch/bin/fs_cli"
	apicommand="global_getvar ALLE_MITARBEITER"
	list_numbers="$( $freeswitch -x "$apicommand" )"

	if [ -n "$list_numbers" ]; then
		echo "$list_numbers" >"$file"
	else
		read -r list_numbers "$file"
	fi

	for number in $list_numbers; do {
		# lars:0162/2666169 -> 01622666169
		echo "$number" | sed 's/[^0-9]//g'
	} done
}
