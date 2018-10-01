#!/bin/bash


VERBOSE=true

. net.assortedminorfixes.util_fns.sh

# Get a list of datasets that should not have automatic snapshots taken (com.sun:auto-snapshot=false)
#  and then find any snapshots in that list which follow the pat of an auto snapshot ([$prefix-]DATEPATTERN--htimepat).
readonly date_pat='20[0-9][0-9]-[01][0-9]-[0-3][0-9]_[0-2][0-9]\.[0-5][0-9]\.[0-5][0-9]'
readonly htime_pat='([0-9]+y)?([0-9]+m)?([0-9]+w)?([0-9]+d)?([0-9]+h)?([0-9]+M)?([0-9]+[s]?)?'

readonly ds_pat='[A-Zabd-z]([[:alnum:]_.:-]/?)*'
readonly snp_pat='[[:alnum:]_.:-]+'
readonly auto_snap_pat="${ds_pat}@(${snp_pat})?${date_pat}--${htime_pat}"

function usage
{
  echo "Usage: $0 [options]"
  echo "  -h: This help"
  echo "  -n: no-act mode, prints what would be done but makes no changes."
  echo "  -v: Verbose"
  echo "  -q: quiet"
  echo "  -a: all snapshots"
  echo "  -o parameter-name: name of parameter to check for auto-snapshot disable. (default: com.sun:auto-snapshot)"
  echo "  -p parameter-name: name of parameter to check each snapshot to determine if it was automatic. (default: not used)"
  echo "  Destroys snapshots on pools that have the auto-snapshot parameter set to false."
  echo "  By default, only destoys pools matching the zfSnap pat for snapshots (override with -a)"
  echo "  (set pools/zfs to be considered for elimination by 'zfs set -o com.sun:auto-snapshot=false <DATASET>'"
  echo "  Specific snapshots are identified by a pattern (overriden with all snapshots) XOR the zfs parameter defined on -p"
}

NOAUTOPARAM="com.sun:auto-snapshot"
DEFISAUTOPARAM="net.shimavak:is-auto-snapshot"
VERBOSE=yes

OPTSPEC=":ho:nvqap"

while getopts "${OPTSPEC}" option
do
  case $option in
    h )
      usage
      exit 0
      ;;
    o )
      NOAUTOPARAM=${OPTARG}
      ;;
    n )
      NOOP="NOOP: "
      ;;
    v )
      VERBOSE=yes
      ;;
    a )
      PATTERN="${ds_pat}@${snp_pat}"
      ;;
    q )
      VERBOSE=
      ;;
    p)
      ISAUTOPARAM=${OPTARG:-$DEFISAUTOPARAM}
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
    *)
      if [ "$OPTERR" != 1 ] || [ "${OPTSPEC:0:1}" = ":" ]; then
	echo "Non-option argument: '-${OPTARG}'" >&2
      fi
      ;;
  esac
done

PATTERN="${PATTERN:-$auto_snap_pat}"

OIFS="${IFS}"
IFS=$'\n\t'

DS_NOAUTO=( $(zfs list -H -o name,com.sun:auto-snapshot | awk -F $'\t' '$2 == "false" { print $1 }') )
if [ ! -z "${ISAUTOPARAM}" ];
then
  AUTO_SNAPS_ON_NOAUTO=( $(zfs list -H -o name,${ISAUTOPARAM} -t snap -r "${DS_NOAUTO[@]}" | awk -F $'\t' '$2 == "true" { print $1 }'  2>/dev/null) )
else
  AUTO_SNAPS_ON_NOAUTO=( $(zfs list -H -o name -t snap -r "${DS_NOAUTO[@]}" | grep -E -e "^${PATTERN}$" 2>/dev/null) )
fi

BAD_SNAPS=( $AUTO_SNAPS_ON_NOAUTO $EMPTY_SNAPS )

if [ ${#BAD_SNAPS[*]} -eq 0 ];
then
	debug "No snaps to remove."
	exit 0
fi

nerrs=0
ERRS=
debug "Destroying snapshots: ${BAD_SNAPS}"
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

for SNAP in ${BAD_SNAPS}
do
	exe zfs destroy "${SNAP}" 
done

IFS="${OIFS}"
