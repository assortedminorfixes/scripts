#!/bin/bash

# Functions used in various scripts

debug() { [ -z "${VERBOSE}" ] || echo "[${BASH_SOURCE}] ${NOOP}$@"; }
exe() { CMD="${1}"; shift; debug "executing ${CMD} ${@@Q}"; [ -z "${NOOP}" ] && ${CMD} "$@" ; }
