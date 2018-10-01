#!/bin/bash

POOL="$1"
shift
TIME=30

while true; do
	OIFS="${IFS}"
	IFS=$'\n'
	STAT="$(zpool status ${POOL})" || exit
	echo "${STAT}" | grep -q 'scrub in progress' || break
	sleep ${TIME}
done
echo "${STAT}" | grep -q 'errors: No known data errors' && $@
