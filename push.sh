#!/bin/sh

add()
{
	local file="$1"

	case "$file" in
		*.sh)
			sh -n "$file" || exit 1
		;;
	esac

	chmod +x "$file" 2>/dev/null
	cp "$file" .
}


PRE="/usr/local/bin"
for FILE in "$PRE/check_incoming_calls.sh" \
	"$PRE/check_internet.sh" \
	"$PRE/cron.backup_server.sh" \
	"$PRE/cron.detect_role.sh" \
	"$PRE/cron.fax_send_spooler.sh" \
	"$PRE/cron.freeswitch_check.sh" \
	"$PRE/cron.monitoring_phones.sh" \
	"$PRE/dial.sh" \
	"$PRE/invoice-calls.sh" \
	"$PRE/monitoring_standalone_generic.sh" \
	"$PRE/print_invoice.sh" \
	"$PRE/restore_mysql.sh" \
	"$PRE/send_admin_message.sh" \
	"/var/www/fusionpbx/dial.php" \
	"/home/ejbw/local_monitoring_phones.sh" \
	"/home/ejbw/do_portfw.sh" \
	"/home/ejbw/sipgateAPI-fax.pl" \
	"/etc/network/interfaces" \
	"/etc/rc.local"; do {
		add "$FILE"
} done

test -d .git || {
	git init
	git config --global user.name  "Bastian Bittorf"
	git config --global user.email "bb@npl.de"
}

git add .
git commit -m "${1:-autocommit}" && git push
