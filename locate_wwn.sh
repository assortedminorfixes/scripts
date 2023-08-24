#!/bin/bash

if [ $# -eq 0 ] 
then 
  echo "Usage: $0 <wwn> [time]" && exit 1
fi

TIMEOUT=${2:-30}

wwn_to_sas() {
  wwn="$1"
  wwnx="${wwn#wwn-}"
  wwnx="${wwnx/naa./0x}"

  printf "0x%x" $((wwnx - (wwnx % 4)))
}

get_sc200_indices() {
  for enc_dev in $(lsscsi -g | awk '/SC200/ { print $(NF) }');
  do
    sg_ses -p aes ${enc_dev} 2>/dev/null | grep -e '^\s*\(Element [0-9]\|SAS address:\)' | tr '\n' ',' | sed 's/\s*Element \([0-9]\+\) descriptor,[^:]*: \([^,]*\),[^:]*: \([^,]*\),/'"${enc_dev//\//\\\/},"'\1,\2,\3\n/g'
  done
}

# check_and_set_led (file, val)
#
# Read an enclosure sysfs file, and write it if it's not already set to 'val'
#
# Arguments
#   file: sysfs file to set (like /sys/class/enclosure/0:0:1:0/SLOT 10/fault)
#   val: value to set it to
#
# Return
#  0 on success, 3 on missing sysfs path
#
check_and_set_led()
{
  file="$1"
  val="$2"

  if [ -z "$val" ]; then
    return 0
  fi

  if [ ! -e "$file" ] ; then
    return 3
  fi

  # If another process is accessing the LED when we attempt to update it,
  # the update will be lost so retry until the LED actually changes or we
  # timeout.
  for _ in 1 2 3 4 5; do
    # We want to check the current state first, since writing to the
    # 'fault' entry always causes a SES command, even if the
    # current state is already what you want.
    read -r current < "${file}"

    # On some enclosures if you write 1 to fault, and read it back,
    # it will return 2.  Treat all non-zero values as 1 for
    # simplicity.
    if [ "$current" != "0" ] ; then
      current=1
    fi

    if [ "$current" != "$val" ] ; then
      echo "$val" > "$file"
    else
      break
    fi
  done
}

sas_to_find="$(wwn_to_sas "$1")"

found=""

for enc in /sys/class/enclosure/*;
do
  for dev in ${enc}/*/device/wwid;
  do
    port="${dev%/device/wwid}"
    portn="${port#${enc}/}"
    wwid="$(wwn_to_sas $(cat "${dev}"))"
    if [ "$wwid" == "$sas_to_find" ]
    then
      echo "Found on $(cat "$enc/device/vendor") $(cat "$enc/device/model") port $portn"
      found=$port
      break 2
    fi
  done
done

if [ ! -z "$found" ]
then
  check_and_set_led "$found/locate" "1"
  [ "$TIMEOUT" -eq 0 ] && exit 0
  sleep "$TIMEOUT"
  check_and_set_led "$found/locate" "0"
  exit 0
fi

# Couldn't find it the easy way, loop through the sgdevs
sc2devs="$(get_sc200_indices)"
for dev in $sc2devs
do
  dev="${dev//,0x0/}"
  dev=( $(echo $dev | tr ',' '\t')  )
  wwid="$(wwn_to_sas ${dev[2]})"
  if [ "$wwid" == "$sas_to_find" ]
  then
    echo "Found on ${dev[0]} port ${dev[1]}"
    found=$port
    break
  fi
done

if [ ! -z "$found" ]
then
  # Found it, set locate bit.
  sg_ses --index=${dev[1]} --set=locate ${dev[0]}
  [ "$TIMEOUT" -eq 0 ] && exit 0
  sleep "$TIMEOUT"
  sg_ses --index=${dev[1]} --clear=locate ${dev[0]}
  exit 0
fi

exit 1
