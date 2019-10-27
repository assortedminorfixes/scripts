#!/bin/bash

VERBOSE=true

debug() { [ -z "${VERBOSE}" ] || echo "[${BASH_SOURCE}] ${NOOP} $@"; }
exe() { CMD="${1}"; shift; debug "executing ${CMD} ${@@Q}"; [ -z "${NOOP}" ] && ${CMD} "$@" ; }

declare -a duplicate
declare -a duplicate_dest

export VIMINIT='source ~/.vim/vimrc|set ts=8 nomod nolist nospell nonu|set colorcolumn= hlsearch incsearch smartcase|nnoremap i <nop>|nnoremap <end> G|nnoremap <home> gg|nnoremap <Space> <C-f>|noremap q :qa!<CR>'

for file in *.mkv
do
  FNAME=( $(find /datapool/Media/Movies -type f -name "${file}" -print -exec false {} +) )
  if [ $? -ne 0 ]
  then
    echo "$file already exists at \"${FNAME[*]}\"" >&2
    duplicate+=("${file}")
    duplicate_dest+=("${FNAME[*]}")
  fi
done
for i in "${!duplicate[@]}"
do
  unset handled
  while [ -z "$handled" ]
  do
    handled=true
    read -n 1 -p "Do you wish to overwrite ${duplicate_dest[i]}? [y/N/(i)nfo]: " -r yesno
    if [ "${yesno,,}" == "y" ]
    then
      :;
    elif [ "${yesno,,}" == "n" -o "${yesno,,}" == "q" -o -z "${yesno}" ]
    then
      echo -e "\nAborting..." >&2
      exit 1
    elif [ "${yesno}" == "i" ]
    then
      vim -d -MR --not-a-term <(mediainfo "${duplicate[i]}") <(mediainfo "${duplicate_dest[i]}")
      echo -en "\033[2K\r"
      unset handled
    else
      echo -en "\033[2K\r"
      unset handled
    fi
  done
done


#exe sudo chown shimavak:plex *.mkv

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
