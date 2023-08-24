#!/bin/bash


VERBOSE=

debug() { [ -z "${VERBOSE}" ] || echo "[${BASH_SOURCE}] ${NOOP}$@"; }
exe() { CMD="${1}"; shift; debug "executing ${CMD} ${@@Q}"; [ -z "${NOOP}" ] && ${CMD} "${@}" ; }

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
      NOOP="n"
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

# EXPIRED_SNAPS
# Search pools with auto-snapshot turned on.
DS_AUTO=( $($ZFS list -H -o name,${DSAUTOPARAM} | awk -F $'\t' '$2 == "true" || $2 == "-" { print $1 }') )

if [ ${#DS_AUTO[@]} -ne 0 ];
then
  # We have a setting for a snapshot to say if it is auto, so use that to dertmine it.
  AUTO_SNAPS_ON_AUTO_MISSING_EXP=( "$($ZFS list -H -o name,${ISAUTOPARAM},${EXPIRESPARAM} -t snap -r "${DS_AUTO[@]}" | awk "$(AWK_FN)"  2>/dev/null)" )

fi

if [ ${#AUTO_SNAPS_ON_AUTO_MISSING_EXP[*]} -ne 0 ];
then
  parallel --halt now,fail=1 --bar -j 1 -C ',' $ZFS set {2} {3} {1} ::: ${AUTO_SNAPS_ON_AUTO_MISSING_EXP[@]}
  exit 0
  for snap in ${AUTO_SNAPS_ON_AUTO_MISSING_EXP[@]}
  do
    exe $ZFS set ${snap//,/ }
    if [ $? -ne 0 ]
    then
      echo "Aborting remaining changes."
      exit 1
    fi
  done
fi

exit 0

