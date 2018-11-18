#!/bin/bash

# DB:
# . /etc/plexupdate.conf && wget -S "http://localhost:32400/diagnostics/databases?X-Plex-Token=${TOKEN}" -O - | funzip > plex.db

# DISK USAGE:
#  sqlite3 plex.db "select file from media_parts where file <> ''" | tr '\n' '\0' | du  -shc --files0-from=- > used_bytes.txt


PREFIX=${PREFIX:-/temppool/Media/}
LOGFILE="./$(basename $0).$$.log"
NELOGFILE="./$(basename $0).$$.NE.log"
#DB=/tmp/com.plexapp.plugins.library.db

umask 002

read -r -d '' SQL <<-EOF
	-- FINAL Rename command
	select
	mp.file
	, (case metai.library_section_id
		when 2 THEN printf('TV Shows/%1s/%s/Season %02i/%s - s%02ie%02i - %s.%s', upper(substr(series_metai.title_sort,1,1)), replace(series_metai.title_sort,'/','⁄'), 
							season_metai.'index', replace(series_metai.title_sort,'/','⁄'), season_metai.'index', metai.'index', replace(metai.title_sort,'/','⁄'), medi.container)
		when 1 THEN printf('Movies/%1s/%s (%4d) - %s.%s', upper(substr(metai.title_sort,1,1)), replace(metai.title_sort,'/','⁄'), metai.year, (case 
			when medi.height > 1100 or medi.width > 3820 then '4k'
			when medi.height > 750 or medi.width > 1900 then '1080p'
			when medi.height > 490 or medi.width > 1260 then '720p'
			else 'SD'
			end
			),medi.container)
		end) as newfile
	--,	metai.title
	--,	metai.id
	 from metadata_items as metai
	inner join media_items as medi
		on medi.metadata_item_id = metai.id 
	inner join media_parts as mp
		on mp.media_item_id = medi.id 
	left join metadata_items as season_metai
		on season_metai.id = metai.parent_id
	left join metadata_items as series_metai
		on series_metai.id = season_metai.parent_id
	WHERE metai.guid NOT LIKE 'iva%' 
	AND mp.file != ""
	and metai.metadata_type in (1,4)
	and metai.library_section_id in (1,2)
	order by newfile
	--limit 2
EOF

function copy_file {

	SOURCE="${1}"
	DEST="${PREFIX}/${2}"


	[ ! -f "${SOURCE}" ] && echo "${SOURCE} doesn't exist, giving up." && exit 1

	DEST_FLDR="$(dirname "${DEST}")"

	if [ ! -d "${DEST_FLDR}" ]
	then
		## Parent folder doesn't exist.
		if [ -f "${DEST_FLDR}" ]
		then
			## Parent folder exists but is a file
			echo "${DEST_FLDR} is not a directory but does exist. Aborting." && exit 2
		fi
		mkdir -p "${DEST_FLDR}" || exit 3
	fi

#	if [ -f "${DEST}" ]
#	then
#		echo "${DEST} already exists. Skipping."
#	else
#		pv -c -N "$(basename ${DEST})" < "${SOURCE}" > "${DEST}" && echo "${SOURCE} -> ${DEST}" || exit 4
#	fi
	if [ -f "${DEST}" ]
	then
		echo "${SOURCE} -> ${DEST}"
	else
		echo ""
		echo "${SOURCE} -> ${DEST}" >> ${NELOGFILE}
	fi
}

# Get DB into temp file.
if [ -z "${DB}" ] || [ ! -f "${DB}" ]
then
	DB=${DB:-$(mktemp)}
	DB_TMP="yes"
	. /etc/plexupdate.conf
 	wget -S "http://127.0.0.1:32400/diagnostics/databases?X-Plex-Token=${TOKEN}" -O - 2>/dev/null | funzip > "${DB}"
fi

OIFS="${IFS}"
IFS=$'\n'
LINES=($(sqlite3 "${DB}" <<< "${SQL}"))
(for line in "${LINES[@]}"
do
	copy_file "${line%%|*}" "${line##*|}"
done) | pv -N TOTAL -l -c -i 20 -s ${#LINES[@]} >> "${LOGFILE}"

[ -z "${DB_TMP}" ] || rm "${DB}"
