#!/bin/bash

. net.assortedminorfixes.util_fns.sh

function usage
{
  echo "Usage: $0 [-h] [-s snapshot_name] [-p prefix] [-r retention] pool"
  echo "-h: This help"
  echo "-n: no-act mode, prints what would be done but makes no changes."
  echo "  Renames a snapshot to match zfsnap format based on its create time and adds a prefix and retention period."
  echo "  Default snapshot_name is 'backup', prefix is 'tape-' and retention is '1m'."
}

POOL=""
SNAPSHOT_NAME="backup"
PREFIX="tape"
RETENTION="1m"
VERBOSE=yes

OPTSPEC=":hs:p:r:nvq"

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
    p )
      PREFIX=${OPTARG}
      ;;
    r )
      RETENTION=${OPTARG}
      ;;
    n )
      NOOP="NO-OP: "
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

DATE_FORMAT="${PREFIX}-%Y-%m-%d_%H.%M.%S--${RETENTION}"

BKUP_CTIME=$(zfs get -H -o value creation ${POOL}@${SNAPSHOT_NAME} 2>/dev/null)

[ $? -ne 0 ] && echo "No zfs snapshot by the name ${POOL}@${SNAPSHOT_NAME}" && exit 1

NEW_SNAPSHOT_NAME=$(echo "${BKUP_CTIME}" | date -f - +${DATE_FORMAT})

# Make sure the snapshot is unmounted, or the rename messes things up.
exe umount -f "${POOL}@${SNAPSHOT_NAME}" 2>/dev/null

# Actually rename the snapshot.
exe zfs rename "${POOL}@${SNAPSHOT_NAME}" "${POOL}@${NEW_SNAPSHOT_NAME}"
