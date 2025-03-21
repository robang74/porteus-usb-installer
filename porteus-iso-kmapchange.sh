#!/bin/bash
#
# (C) 2025, Roberto A. Foglietta <roberto.foglietta@gmail.com> - 3-clause BSD
#
################################################################################
set -e

trap "echo; echo; exit 1" INT

shs=$(basename $0)

isodd() { dd ${2:+if=$2} bs=1M $1 status=none; }
isoch() { isodd count=1 $1 | sed -e "s,# kmap=br,kmap=$2  ,"; isodd skip=1 $1; }
isodo() { isoch $1 $2 | isodd of=$3; sync $3; }

if ! test -r "$1" -a -n "$2" -a -n "$3"; then
    echo
    echo "USAGE: $shs </path/file.iso> <it> <boot.iso>"
    echo
    exit 1
fi

if [ -b "$3" -a "x$4" != "x--write-on-device" ]; then
    echo
    echo "WARNING: to overwrite a block device use this argument"
    echo "         --write-on-device after the /dev/sdX to write,"
    echo "         beware on that device's ALL data will be LOST."
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
