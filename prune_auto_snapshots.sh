#!/bin/bash


VERBOSE=v

debug() { [ -z "${VERBOSE}" ] || echo "[${BASH_SOURCE}] ${NOOP}$@"; }

ZFS=/sbin/zfs

# Get a list of datasets that should not have automatic snapshots taken (${DSAUTOPARAM}=false)
#  and then find any snapshots in that list which follow the pat of an auto snapshot ([$prefix-]DATEPATTERN--htimepat).
readonly date_pat='20[0-9][0-9]-[01][0-9]-[0-3][0-9]_[0-2][0-9]\.[0-5][0-9]\.[0-5][0-9]'
readonly htime_pat='([0-9]+y)?([0-9]+m)?([0-9]+w)?([0-9]+d)?([0-9]+h)?([0-9]+M)?([0-9]+[s]?)?'

readonly ds_pat='[A-Zabd-z]([[:alnum:]_.:-]/?)*'
readonly snp_pat='[[:alnum:]_.:-]*'
readonly auto_snap_pat="${ds_pat}@(${snp_pat})?${date_pat}--${htime_pat}"

# FN def not used later as we want to parse auto_snap_pat from cmdline if it changes.
function AWK_FN
{
  echo 'BEGIN {
  OFS=",";
};
function time2s(str) {
  match(str, /([0-9]+)y/, ys);
  match(str, /([0-9]+)m/, ms);
  match(str, /([0-9]+)w/, ws);
  match(str, /([0-9]+)d/, ds);
  match(str, /([0-9]+)h/, hs);
  match(str, /([0-9]+)M/, Ms);
  match(str, /([0-9]+)s/, ss);
  return((((ys[1]*365+ms[1]*30+ws[1]*7+ds[1])*24+hs[1])*60+Ms[1])*60+ss[1]);
};
$1 ~ /'${PATTERN//\//\\/}'/ && $2 == "-" {
  a=mktime(gensub(/[^0-9]/, " ", "g", gensub(/.*('${date_pat}')--'${htime_pat}'$/, "\\1", "g", $1)));
  b=time2s(gensub(/.*--('${htime_pat}')$/, "\\1", "g", $1));
  print $1, "'${ISAUTOPARAM}'=true", "'${EXPIRESPARAM}'=" a+b;
}'
}

DSAUTOPARAM="com.sun:auto-snapshot"
ISAUTOPARAM="net.assortedminorfixes:is-auto-snapshot"
EXPIRESPARAM="net.assortedminorfixes:snapshot-expire"

function usage
{
  echo "Usage: $0 [options]"
  echo "  -h: This help"
  echo "  -n: no-act mode, prints what would be done but makes no changes."
  echo "  -v: Verbose"
  echo "  -q: quiet"
  echo "  -a: all snapshots"
  echo "  -E/e: [Only] Remove empty snapshots.  Default: Don't remove empty snapshots."
  echo "  -o parameter-name: name of parameter to check for auto-snapshot disable. (default: ${DSAUTOPARAM})"
  echo "  -p parameter-name: name of parameter to check each snapshot to determine if it was automatic. (default: ${ISAUTOPARAM:-not used})"
  echo "  -x parameter-name: name of parameter to check for snapshot expiration. (default: ${EXPIRESPARAM})"
  echo "  Destroys snapshots on pools that have the auto-snapshot parameter set to false."
  echo "  By default, only destoys snapshots matching the zfSnap pat for snapshots (override with -a)"
  echo "  (set pools/zfs to be considered for elimination by 'zfs set -o ${DSAUTOPARAM}=true <DATASET>'"
  echo "  Specific snapshots are identified by a pattern (overriden with all snapshots) XOR the zfs parameter defined on -p"
}

function simplify_snapshot_list
{
  declare -n SNAPS="$1"
  local IFS=$'\n'
  echo "${SNAPS[*]}"| LC_ALL=C sort -u | awk 'BEGIN{FS="@";ORS="";OFS="";};{if(VOL!=$1){VOL=$1;print TRS VOL "@";TRS="\n";TFS="";}print TFS $2;TFS=",";}'
}


function clean_snapshot_list
{
  local _retname=$1
  eval 'local SNAP_NAMES=( "${'"$1"'[@]}" )'
  local VOLLIST=( "$(printf "%s\n" "${SNAP_NAMES[@]%@*}" | sort -u )" )
  local TMP_LIST
  for VOL in ${VOLLIST}
  do
    TMP_LIST=( "${TMP_LIST[@]}" "$(printf "%s\n" "${SNAP_NAMES[@]}" | awk -v VOL="$VOL" 'BEGIN { FS="@"; ORS=""; OFS=""; print VOL "@";}; $1 == VOL { print TRS $2; TRS="," }')" )
  done

  eval $_retname='( "${TMP_LIST[@]}" )'
}

OPTSPEC=":ho:nvqap:x:Ee"

while getopts "${OPTSPEC}" option
do
  case $option in
    h )
      usage
      exit 0
      ;;
    o )
      DSAUTOPARAM=${OPTARG}
      ;;
    n )
      NOOP="NOOP: "
      ;;
    v )
      VERBOSE="v"
      ;;
    a )
      PATTERN="${ds_pat}@${snp_pat}"
      ;;
    q )
      VERBOSE=
      ;;
    x )
      EXPIRESPARAM=${OPTARG}
      ;;
    p )
      ISAUTOPARAM=${OPTARG}
      ;;
    P )
      unset ISAUTOPARAM
      ;;
    e )
      REMOVE_EMPTY=true
      ;;
    E )
      REMOVE_EMPTY="ONLY"
      ;;
    \? )
      echo "Invalid option: -$OPTARG" >&2
      usage
      exit 1
      ;;
    : )
      echo "Option -$OPTARG requires an argument." >&2
      usage
      exit 1
      ;;
    * )
      if [ "$OPTERR" != 1 ] || [ "${OPTSPEC:0:1}" = ":" ]; then
	echo "Non-option argument: '-${OPTARG}'" >&2
      fi
      ;;
  esac
done

PATTERN="${PATTERN:-$auto_snap_pat}"

OIFS="${IFS}"
IFS=$'\n\t'

[ -z "$NOOP" ] || ZFSOPTS="n"
[ -z "$VERBOSE" ] || ZFSOPTS="${ZFSOPTS}v"
[ -z "$ZFSOPTS" ] || ZFSOPTS="-${ZFSOPTS}"

if [ ! "${REMOVE_EMPTY}" = "ONLY" ]
then

  # List of pools which should not have auto-snapshots.
  DS_NOAUTO=( $($ZFS list -H -o name,${DSAUTOPARAM} | awk -F $'\t' '$2 == "false" { print $1 }') )
  if [ ${#DS_NOAUTO[@]} -ne 0 ];
  then
    if [ ! -z "${ISAUTOPARAM}" ];
    then
      # We have a setting for a snapshot to say if it is auto, so use that to dertmine it.
      AUTO_SNAPS_ON_NOAUTO=( $($ZFS list -H -o name,${ISAUTOPARAM} -t snap -r "${DS_NOAUTO[@]}" | awk -F $'\t' '$2 == "true" { print $1 }'  2>/dev/null) )
    else
      # No setting, so assume that auto-snapshots follow the pattern.
      AUTO_SNAPS_ON_NOAUTO=( $($ZFS list -H -o name -t snap -r "${DS_NOAUTO[@]}" | grep -E -e "^${PATTERN}$" 2>/dev/null) )
    fi
  fi


  # EXPIRED_SNAPS
  # Search pools with auto-snapshot turned on.
  DS_AUTO=( $($ZFS list -H -o name,${DSAUTOPARAM} | awk -F $'\t' '$2 == "true" || $2 == "-" { print $1 }') )

  if [ ${#DS_AUTO[@]} -ne 0 ];
  then
    if [ ! -z "${ISAUTOPARAM}" ];
    then
      # We have a setting for a snapshot to say if it is auto, so use that to dertmine it.
      AUTO_SNAPS_ON_AUTO="$($ZFS list -H -o name,${ISAUTOPARAM},${EXPIRESPARAM} -t snap -r "${DS_AUTO[@]}" | awk 'BEGIN { FS="\t"; OFS=","; }; $2 == "true" { print $1,$3 }'  2>/dev/null)"

      # First filter for expires param, if all of the results have it, then we can use awk, otherwise we will have to parse the names.
      echo "${AUTO_SNAPS_ON_AUTO}" | grep -E -e ",-$" 2>/dev/null >/dev/null
      if [ $? -ne 0 ]
      then
	# All snaps have expiration epochs.
	debug "No bad expirations..."
	EXPIRED_SNAPS=( $(echo "${AUTO_SNAPS_ON_AUTO}" | awk 'BEGIN { FS=","; now=systime() }; $2 <= now { print $1 }' ) )
	unset AUTO_SNAPS_ON_AUTO
      else
	debug "Some bad expirations, just use file name."
	AUTO_SNAPS_ON_AUTO=( $(echo "${AUTO_SNAPS_ON_AUTO}" | awk 'BEGIN { FS=","; }; { print $1 }' ) )
      fi
    else
      # No setting, so assume that auto-snapshots follow the pattern.
      debug "Finding snapshots based on pattern."
      AUTO_SNAPS_ON_AUTO=( $($ZFS list -H -o name -t snap -r "${DS_AUTO[@]}" | grep -E -e "^${PATTERN}$" 2>/dev/null) )
    fi
  fi

  if [ ${#AUTO_SNAPS_ON_AUTO[*]} -ne 0 ];
  then

    EXPIRED_SNAPS=( $(echo "${AUTO_SNAPS_ON_AUTO[*]}" | awk "$(AWK_FN)") )

  fi



  BAD_SNAPS=( "${AUTO_SNAPS_ON_NOAUTO[@]}" "${EXPIRED_SNAPS[@]}" )


  if [ ${#BAD_SNAPS[*]} -eq 0 ];
  then
    debug "No auto snaps to remove."
  else
    nerrs=0
    ERRS=
    debug "Destroying ${#BAD_SNAPS[@]} snapshots: ${BAD_SNAPS[*]}"
    for SNAP in ${BAD_SNAPS}
    do
      if [ "${SNAP}" = "${SNAP//@/}" ]
      then
	ERRS=( "${ERRS[*]}" "$SNAP" )
	(( nerrs++ ))
      fi
    done

    if [ $nerrs -ne 0  ]
    then
      echo "ERROR: Snapshot(s) [${ERRS[@]} does not appear to be a snapshot (no @ in name), aborting!  No snaps have been destroyed." >&2
      exit $nerrs
    fi


    BAD_SNAPS=( "$(simplify_snapshot_list BAD_SNAPS )" )
    for SNAP in ${BAD_SNAPS[@]}
    do
      echo "Destroying snap \"${SNAP}\"."
      $ZFS destroy $ZFSOPTS "${SNAP}" 
      if [ $? -ne 0 ];
      then
	echo "Problem with Snap \"${SNAP}\"."
	break
      fi
    done

  fi


fi

if [ ! -z ${REMOVE_EMPTY} ];
then
  EMPTY_SNAPS=( $($ZFS list -H -o name,used -t snap | awk -F $'\t' '$2 == "0B" { print $1 }' ) )
fi

if [ ${#EMPTY_SNAPS[*]} -eq 0 ];
then
  debug "No empty snaps to remove."
else
  EMPTY_SNAPS=( "$(simplify_snapshot_list EMPTY_SNAPS)" )

  for SNAP in ${EMPTY_SNAPS[@]}
  do
    $ZFS destroy $ZFSOPTS "${SNAP}" || exit
  done
fi

IFS="${OIFS}"
