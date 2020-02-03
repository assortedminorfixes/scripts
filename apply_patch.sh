#!/bin/bash

# Quick script to apply patches to plex to fix some issues in the plug-in interface after updates.

PLEX_DIR="$(dpkg-query -L "`dpkg -f "${1}" Package`" | grep Plug-ins | head -1)"

pushd "${PLEX_DIR}" || exit 1

patch -p0 < /etc/plexupdate.d/plex.patch
