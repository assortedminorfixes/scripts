#!/bin/bash


. net.assortedminorfixes.util_fns.sh

function usage
{
  echo "-h: This help"
  echo "-n: no-act mode, prints what would be done but makes no changes."
  echo "-v: Verbose"
  echo "-q: quiet"
  echo "Usage: $0 [-h] [-s snapshot_name] pool"
  echo "  Creates a snapshot for backup purposes.  Default snapshot_name is 'backup'."
  echo "  Will abort if snapshot already exists."
}

SNAPSHOT_NAME="backup"
VERBOSE=yes

OPTSPEC=":hs:nvq"

while getopts "${OPTSPEC}" option
do
  case $option in
    h )
      usage
      exit 0
      ;;
    s )
      SNAPSHOT_NAME=${OPTARG}
      ;;
    n )
      NOOP="NOOP: "
      ;;
    v )
      VERBOSE=yes
      ;;
    q )
      VERBOSE=
      ;;
    \? )
      echo "Invalid option: -$OPTARG" >&2
      exit 1
      ;;
    : )
      echo "Option -$OPTARG requires an argument." >&2
      exit 1
      ;;
    *)
      if [ "$OPTERR" != 1 ] || [ "${OPTSPEC:0:1}" = ":" ]; then
	echo "Non-option argument: '-${OPTARG}'" >&2
      fi
      ;;
  esac
done

shift $((OPTIND -1))

POOL="$1"
if [ -z "$POOL" ]
then
	usage
	exit 1
fi

BKUP_EXISTS=$(zfs list ${POOL}@${SNAPSHOT_NAME} 2>/dev/null)

[ $? -eq 0 ] && echo -e "Snapshot ${POOL}@${SNAPSHOT_NAME} already exists, backup may be in progress.\n"\
\	"Please check the status of the backup and if needed, rename snapshot ${POOL}@${SNAPSHOT_NAME}" && exit 1

exe zfs snap "${POOL}@${SNAPSHOT_NAME}"
