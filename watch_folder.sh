#!/bin/bash

# Modified from stackexchange answer by mr.spuratic
#  https://unix.stackexchange.com/questions/305394/script-to-monitor-for-new-files-in-a-shared-folder-windows-host-linux-guest/305452#305452

MONITOR_FOLDER=/datapool/Media/InProgress/export/converted
#SUB_FOLDER=.
PROGRAM="$1"
LOCK_DIR="/var/lock/mediawatch.lock"
SUFFIX="complete"
MODIFY_DELAY=0



if mkdir "$LOCK_DIR"; then
  ( 
  export LC_COLLATE=C  # for sort
  cd "$MONITOR_FOLDER"
  touch .dirlist.old
  find "${SUB_FOLDER:-.}" -maxdepth 1 -type f -mmin +${MODIFY_DELAY} -iname "*.${SUFFIX}" -a \! -name ".dirlist.*" > .dirlist.new
  if [[ -f  .dirlist.old ]] 
  then
    comm -13 <(sort .dirlist.old) <(sort .dirlist.new) |
      while read -r file; do
	"$PROGRAM" "${file}"
      done
  fi
  mv .dirlist.new .dirlist.old
  )
  rmdir "$LOCK_DIR"
else
  logger -p local0.notice "mediawatch.lock found, skipping run"
fi
