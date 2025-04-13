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

variant="porteux"
store_dirn="moonwalker"
usage_strn="/path/$variant-bla-bla.iso [/dev/]sdx [it]"

export DEVEL=${DEVEL:-0}

function perr() { { printf "$@"; } >&2; }
function errexit() { echo; exit ${1:-1}; }

function usage() {
    printf \\n"USAGE: bash ${shs:-$(basename $0)} $usage_strn"\\n
    eval "$@"
}

function search() {
    local d ldirs=". $wdr $workingd_path .." f="${1:-}"
    test -n "$f" || return 1
    test "$(basename $wdr)"  == "tmp" && ldirs="$ldirs .."
    for d in $ldirs; do
        if [ -d "$d" -a -r $d/$f ]; then echo "$d/$f"; return 0; fi
    done; return 1
}

function missing() {
    perr \\n"ERROR: file '${1:-}' is missing or wrong type, abort!"\\n
    errexit
}

script=$(search porteus-usb-install.sh ||:)
isofile=${1:-}
dev=${2:-1}

test -b "$dev" || dev="/dev/$dev"
test -b "$dev" || missing "$dev"
test -r "$script" || missing "$script"
test -r "$isofile" || missing "$isofile"

if ! echo "$isofile" | grep -qi "$variant"; then    
    usage errexit
    perr "ERROR: this script requires a '$variant' ISO image file"\\n
fi

DEVEL=$DEVEL VARIANT=$variant bash $script "$isofile" $dev ${3:-} --ext4-install
