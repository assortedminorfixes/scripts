#!/bin/bash

# Default mode, move directory, moves files into appropriate folder based on folder name (e.g. A-D, etc.) using globbing.

# Added mode to move a single file to the correct folder if passed a single file as input.

VERBOSE=true

debug() { [ -z "${VERBOSE}" ] || echo "[${BASH_SOURCE}] ${NOOP} ${@}"; }
exe() { CMD="${1}"; shift; debug "executing ${CMD} ${@@Q}"; [ -z "${NOOP}" ] && ${CMD} "${@}" ; }
error() { echo -e "${@}" >&2 ; }

DESTFOLDER=/datapool/Media/Movies

declare -a duplicate
declare -a duplicate_dest

export VIMINIT='source ~/.vim/vimrc|set ts=8 nomod nolist nospell nonu|set colorcolumn= hlsearch incsearch smartcase|nnoremap i <nop>|nnoremap <end> G|nnoremap <home> gg|nnoremap <Space> <C-f>|noremap q :qa!<CR>'


move_single_file()
{
  local file="${1}"
  local FN="`basename "${file}"`"
  FN="${FN^}" # Correct first letter to uppercase
  firstletter="${FN:0:1}"
  debug "-${FUNCNAME[0]} \"${file}\" (FN=$FN, firstletter=$firstletter)"
  exe chmod 0664 "${file}"
  for dir in "${DESTFOLDER}"/*
  do
    glob="`basename "${dir}"`"
    debug "--${FUNCNAME[0]}: globbing for dir \"$dir\", glob=$glob"
    if [[ "${firstletter}" == [${glob}] ]] 
    then
      exe mv "${file}" "${dir}/${FN}"
      return
    fi
  done

  # Only get here if we didn't move the file.
  echo "-${FUNCNAME[0]} unable to find destination folder for \"${file}\", skipping..."
}

find_duplicate()
{
  # Looks for file in destination folder and returns true if one is found.
  local retval=-1
  local FNAME="${1}"
  debug "-${FUNCNAME[0]} Checking ${FNAME}"
  if [ "${FNAME}" == '*.mkv' ]
  then
    echo "There are no mkv files in the current directory.  Aborting."
    exit 1
  fi
  local file="$(basename "${FNAME}")"
  DFNAME=( $(find "${DESTFOLDER}" -type f -name "${file}" -print -exec false {} +) )
  if [ ${?} -ne 0 ]
  then
    error "${file} already exists at \"${DFNAME[@]}\""
    duplicate+=("${FNAME}")
    duplicate_dest+=("${DFNAME[*]}")
    retval=0
  fi
  debug "-${FUNCNAME[0]} Done Checking ${file}. (DFNAME=$DFNAME)"
  return ${retval}
}

prompt_duplicate()
{
  local i=${1:-0}
  local ORIGIN_FILE="${duplicate[i]}"
  local DEST_FILE="${duplicate_dest[i]}"
  debug "-${FUNCNAME[0]}  index $i (${ORIGIN_FILE}, ${DEST_FILE}) in `pwd`"
  unset handled
  while [ -z "${handled}" ]
  do
    handled=true
    read -n 1 -p "Do you wish to overwrite ${DEST_FILE}? [y/N/(i)nfo/(q)uit]: " -r yesno
    if [ "${yesno,,}" == "y" ]
    then
      :;
    elif [ "${yesno,,}" == "n" -o "${yesno,,}" == "q" -o -z "${yesno}" ]
    then
      error "\nAborting..."
      exit 1
    elif [ "${yesno}" == "i" ]
    then
      vim -d -MR --not-a-term <(mediainfo "${ORIGIN_FILE}") <(mediainfo "${DEST_FILE}")
      echo -en "\033[2K\r"
      unset handled
    else
      echo -en "\033[2K\r"
      unset handled
    fi
  done
}


if [ -z "${1}" -o -d "${1}" ]
then
  mode="directory"
  # Use set to set the positional parameter 1 ($1) to the current directory (.) if no dir was passed.
  #  This emulates the previous operation mode.
  [ -z "${1}" ] && set -- .
else
  mode="single"
fi



if [ "${mode}" == "directory" ];
then
  debug "Directory Mode"
  while [ -d "${1}" ]
  do
    pushd "${1}"
    for file in *.mkv
    do
      debug "Directory Mode: Checking ${file}"
      find_duplicate "${file}"
    done
    for i in "${!duplicate[@]}"
    do
      prompt_duplicate $i
    done


    #exe sudo chown shimavak:plex *.mkv

    exe chmod 0664 *.mkv

    for dir in ${DESTFOLDER}/*; 
    do 
      # This bit of magic finds the correct directory for this file based on the first letter of the file name.
      # This works because the folders are named [A-D] which follows the shell globbing pattern.
      # So, we look for all files (f) in the current directory which go i.e. [0-D]*.mkv and move them into that folder.
      # This works because if bash doesn't find a file which matches [0-D]*.mkv, it will assume that you meant the file
      # to be literally named '[0-D]*.mkv' and so will return that.  Thus, if we get ${f} == '[0-D]*.mkv' (which is what
      # we get when we quote the string...that is, no globbing happens) then we know there are no files and we don't try
      # to copy them.
      glob="`basename "${dir}"`"
      f=( [${glob}]*.mkv ); 
      [ "${f}" != "[${glob}]*.mkv" ] && exe mv [${glob}]*.mkv ${dir}/; 

    done
    # If we were in a subdir, pop back our and shift out the variable, otherwise, let the do loop break it
    [ -d "${1}" ] && popd
    shift || break
  done
else # mode != directory
  debug "Single Mode"
  while [ -f "${1}" ]
  do
    file="${1}"

    if [ "${file##*.}"  == "complete" ]
    then
      if [ -f "${file%.complete}.mkv" ]
      then
	file="${file%%.complete}.mkv"
      else 
	echo "${file%.complete}.mkv does not exist, exiting."
       	exit 1
      fi
    fi

    debug "Single Mode: Working with ${file}"
    BFNAME="`basename "${file}"`"

    if find_duplicate "${file}"
    then
      # File already exists, abort in non-interactive mode, prompt in interactive mode.
      if [ -t 0 ] # Interactive mode
      then
	prompt_duplicate
      else
	error "Duplicates found, running in batch mode, aborting."
	exit 1
      fi
    fi

    move_single_file "${file}"

    shift || break
  done

fi 
