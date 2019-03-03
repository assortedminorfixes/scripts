#!/bin/bash

VERBOSE=true

debug() { [ -z "${VERBOSE}" ] || echo "[${BASH_SOURCE}] ${NOOP}$@"; }
exe() { CMD="${1}"; shift; debug "executing ${CMD} ${@@Q}"; [ -z "${NOOP}" ] && ${CMD} "$@" ; }

for file in *.mkv
do
  FNAME=( $(find /datapool/Media/Movies -type f -name "${file}" -print -exec false {} +) )
  if [ $? -ne 0 ]
  then
    echo "$file already exists at \"${FNAME[*]}\"" >&2
    duplicate=true
  fi
done
while [ ! -z "$duplicate" ]
do
  read -n 1 -p "Do you wish to overwrite? [y/N]: " -r yesno
  if [ "${yesno}" == "y" -o "${yesno}" == "Y" ]
  then
    unset duplicate
  elif [ "${yesno}" == "n" -o "${yesno}" == "N" -o -z "${yesno}" ]
  then
    echo -e "\nAborting..." >&2
    exit 1
  fi
  echo
done

exe sudo chown shimavak:plex *.mkv

exe chmod 0664 *.mkv

for dir in /datapool/Media/Movies/*; 
do 
  # This bit of magic finds the correct directory for this file based on the first letter of the file name.
  # This works because the folders are named [A-D] which follows the shell globbing pattern.
  # So, we look for all files (f) in the current directory which go i.e. [0-D]*.mkv and move them into that folder.
  # This works because if bash doesn't find a file which matches [0-D]*.mkv, it will assume that you meant the file
  # to be literally named '[0-D]*.mkv' and so will return that.  Thus, if we get $f == '[0-D]*.mkv' (which is what
  # we get when we quote the string...that is, no globbing happens) then we know there are no files and we don't try
  # to copy them.
  f=( [${dir##*/}]*.mkv ); 
  [ "$f" != "[${dir##*/}]*.mkv" ] && exe mv [${dir##*/}]*.mkv $dir/; 
done
