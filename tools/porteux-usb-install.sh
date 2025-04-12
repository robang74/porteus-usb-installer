#!/bin/bash
#
# (C) 2025, Roberto A. Foglietta <roberto.foglietta@gmail.com> - 3-clause BSD
#
################################################################################
set +o noclobber
set +u
set -e

usage_strn="/path/porteux-bla-bla.iso [/dev/]sdx [it]"

function usage() {
    printf \\n"USAGE: bash ${shs:-$(basename $0)} $usage_strn"\\n
    eval "$@"
}

script=$(search porteus-usb-install.sh ||:)
isofle=${1:-}
dev=${2:-1}

test -r $isofile || missing $isofile
test -r $script || missing $script
test -b $dev || missing $dev

echo "$isofle" | grep -qi "porteux" || usage exit 1

DEVEL=${DEVEL:-0} VARIANT=porteux bash $script $isofle $dev ${3:-} --ext4-install
