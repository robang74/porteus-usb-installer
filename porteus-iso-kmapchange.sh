#!/bin/bash
#
# (C) 2025, Roberto A. Foglietta <roberto.foglietta@gmail.com> - 3-clause BSD
#
################################################################################
set +o noclobber
set +u
set -e

wdr=$(dirname "$0")
shs=$(basename "$0")
usage_strn="/path/file.iso it <boot.iso | /dev/sdX --write-on-device>"

function isdevel() { test "$DEVEL" == "${1:-1}"; }
function perr() { { echo; echo "$@"; } >&2; }
function errexit() { echo; exit ${1:-1}; }

function usage() {
    perr "USAGE: bash ${shs:-$(basename $0)} $usage_strn"
    eval "$@"
}

if [ "x$1" == "x-h" -o "x$1" == "x--help" ]; then ##############################
    usage echo
else ###########################################################################

trap "echo; echo; exit 1" INT

isodd() { dd ${2:+if=$2} bs=1M $1 status=none; }
isoch() { isodd count=1 $1 | sed -e "s,# kmap=br,kmap=$2  ,"; isodd skip=1 $1; }
isodo() { isoch $1 $2 | isodd of=$3; sync $3; }

if ! test -r "$1" -a -n "$2" -a -n "$3"; then
    usage errexit 1
fi

if [ -b "$3" -a "x$4" != "x--write-on-device" ]; then
    echo
    echo "WARNING: to overwrite a block device use this argument"
    echo
    echo "         --write-on-device /dev/sdX for direct access,"
    echo
    echo "         consider that device's ALL data will be LOST."
    echo
    exit 1
fi

printf "\nRunning '$shs'\n"
printf "\n-> file: $1"
printf "\n-> isow: $3 ${4:+($4)}"
printf "\n-> lang: $2\n"
test -b "$1" && umount $1?
time isodo $1 $2 $3
test -b "$1" && eject $1
echo

fi #############################################################################
