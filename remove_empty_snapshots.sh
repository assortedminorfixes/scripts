#!/bin/bash

EMPTY_SNAPS=( $(zfs list -H -o name,used -t snap | grep '@\w\+ly.*\s0B$' | sed -e 's/\s\+0B$//') )

for snap in ${EMPTY_SNAPS[*]};
do
	zfs destroy "${snap}"
done
