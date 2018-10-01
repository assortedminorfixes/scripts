#!/bin/bash

export LANG=en_US.UTF8
export NCURSES_NO_UTF8_ACS=1

exec 3>&1
choice=$(tmux list-sessions | awk 'BEGIN { FS=":"; } { st = index($0,":"); print $1 " \"" substr($0,st+2) "\""; } ; END { print "C \"Create named session\"\nN \"New Session\"" }' |\
	xargs dialog --ok-label 'Attach' --cancel-label 'Cancel' --menu tmux 20 80 20 2>&1 1>&3 ) || exit $?

if [ "${choice}" = "C" ]; then
	custom_name=$(dialog --inputbox "Session Name" 8 80 2>&1 1>&3 )
	[ $? ] && tmux new -s "${custom_name}" || tmux
elif [ "${choice}" = "N" ]
then
	tmux
else
	tmux attach-session -t ${choice}
fi
