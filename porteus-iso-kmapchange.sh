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

store_dirn="moonwalker"
usage_strn="/path/file.iso it <boot.iso | /dev/sdX --write-on-device>"

export DEVEL=${DEVEL:-0}

# RAF: these values depend by external sources and [TODO] should be shared #____

# RAF: internal values #________________________________________________________

# RAF: basic common functions #_________________________________________________

function askinghelp() { test "x$1" == "x-h" -o "x$1" == "x--help"; } 
function isondemand() { echo "$0" | grep -q "/dev/fd/"; }
function isdevel() { test "${DEVEL:-0}" != "0"; }
function perr() { { echo; echo -e "$@"; } >&2; }
function errexit() { echo; exit ${1:-1}; }

function amiroot() {
    test "$EUID" == "0" -o "$ID" == "0" -o "$(whoami)" == "root"
}

function usage() {
    perr "USAGE: bash ${shs:-$(basename $0)} $usage_strn"
    eval "$@"
}

# RAF: basic common check & set #_______________________________________________

if isondemand; then
    wdr=$PWD
    perr "###############################################"
    perr "This is an on-demand from remote running script"
    perr "###############################################"
fi

workingd_path=$(dirname $(realpath "$0"))
download_path=${download_path:-$PWD}
if [ "$(basename $PWD)" != "$store_dirn" ]; then
    download_path="$download_path/$store_dirn"
fi

if isdevel; then
    perr "download path: $download_path\nworkingd path: $workingd_path"
else
    # RAF: this could be annoying for DEVs but is an extra safety USR checkpoint
    sudo -k
fi

# RAF: internal check & set and early functions #_______________________________

isodd() { dd ${2:+if=$2} bs=1M $1 status=none; }
isoch() { isodd count=1 $1 | sed -e "s,# kmap=br,kmap=$2  ,"; isodd skip=1 $1; }
isodo() { isoch $1 $2 | isodd of=$3; sync $3; }

################################################################################
if askinghelp; then usage errexit 0; else ######################################

trap "echo; echo; exit 1" INT

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
