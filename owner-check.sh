#!/bin/bash
set -e

[ -z "$server" -o -z "login" ] && { echo '$server and $login need to be set'; exit 1 }

header=
from=systemd-maint@fedoraproject.org
time='2 years ago'
# time='1 day ago'
port=587

for user in "$@"; do
    echo "checking $user…"
    t=$(git shortlog --all --author $user --since "@{$time}" | wc -l)
    if [ $t != 0 ]; then
	echo "$t commits in the last two years, OK"
	continue
    fi

    if [ -z "$header" ]; then
	echo '$USER$;$EMAIL$' >.mail.list
	header=done
    fi

    echo "$user;$user@fedoraproject.org" >>.mail.list
done

[ -z "$header" ] && exit 0

echo "Sending mails…"
set -x
massmail -F $from \
	 -C $from \
	 -S 'write access to the fedora systemd package' \
	 -z $server -u $login -P $port \
	 .mail.list <owner-check.template
