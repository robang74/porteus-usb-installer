#!/bin/bash
#
# (C) 2025, Roberto A. Foglietta <roberto.foglietta@gmail.com> - 3-clause BSD
#
################################################################################
set -e

wdr=$(dirname "$0")
shs=$(basename "$0")
usage_strn="[<type> <url> <arch> <vers>] [/dev/sdx] [it]"

# Script package to download and script name to execute
zpkg="v0.2.8.tar.gz"
repo="https://github.com/robang74/porteus-usb-installer"
zurl="$repo/archive/refs/tags"
scrp="porteus-usb-install.sh"

################################################################################

function isdevel() { test "$DEVEL" == "${1:-1}"; }
function perr() { { echo; echo "$@"; } >&2; }
function errexit() { echo; exit ${1:-1}; }

function usage() {
    perr "USAGE: bash ${shs:-$(basename $0)} $usage_strn"
    eval "$@"
}

function missing() {
    perr "ERROR: file '${1:-}' is missing, abort!"
    errexit
}

function sure() {
    local ans
    echo
    read -p "Are you sure to continue [N/y] " ans
    ans=${ans:0:1}
    test "$ans" == "Y" -o "$ans" == "y" && return 0
    errexit
}

function waitdev() {
    partprobe
    for i in $(seq 1 100); do
        egrep " $1$" /proc/partitions && return 0
        sleep 0.1
    done
    perr "ERROR: waitdev('$1') failed, abort!"
    errexit
}

function mke4fs() {
    local lbl=$1 dev=$2; shift 2
    mkfs.ext4 -L $lbl -E lazy_itable_init=1,lazy_journal_init=1 -F $dev "$@"
}

function search() {
    local f=$1
    if [ -r "$f" ]; then echo "$f"; return 0; fi 
    if [ -r "$wdr/$f" ]; then echo "$wdr/$f"; return 0; fi
    return 1
}

function download() {
    local opt
    if [ "x$1" == "x-c" ]; then
        opt="-c"; shift
    fi
    local f url=$1; shift
 
    for f in "$@"; do
        if [ ! -n "$opt" ]; then search "$f" >/dev/null && continue; fi
        echo
        echo "Downloading file: $f"
        sure
        wget -q --show-progress $opt $url/$f || errexit
    done
}

function isocheck() {
    printf "\nChecking '$1' sha256sum ... "
    if sha256sum $1 2>/dev/null | grep -qw "$2"; then
        printf "OK\n"
    else
        printf "KO\n"
        return 1
    fi
}

if [ "x$1" == "x-h" -o "x$1" == "x--help" ]; then ##############################
    usage echo
else ###########################################################################

if isdevel; then
   zurl="$repo/archive/refs/heads"
   zpkg="main.tar.gz"
fi

trap "echo; echo; exit 1" INT

if echo "$1" | grep -qe "^/dev/"; then
    if [ -b "$1" ]; then
        set -- "" "" "" "" "$@"
    else
        perr "ERROR: block device '$1' is not valid, abort!"
        errexit
    fi
fi

type=${1^^}
type=${type:-MATE}
#uweb=${2:-https://linux.rz.rub.de}
uweb=${2:-https://mirrors.dotsrc.org}
arch=${3:-x86_64}
vers=${4:-current}
bdev=$5
lang=$6
shf="sha256sums.txt"
url="$uweb/porteus/$arch/$vers"

mkdir -p porteus; pushd porteus
declare -i tms=$(date +%s%N)

download $url $shf
shf=$(search $shf)
chk=$(grep -ie "porteus.*-${type}-.*.iso" $shf | cut -d' ' -f1)
iso=$(grep -ie "porteus.*-${type}-.*.iso" $shf | tr -s ' ' | cut -d' ' -f2)

iso=$(search $iso || echo $iso)
if ! isocheck $iso $chk; then
    download -c $url $iso
    iso=$(search $iso)
    if ! isocheck  $iso $chk; then
        rm -f $iso
        errexit
    fi
fi

if [ "$DEVEL" == "1" ]; then
    rm -f $zpkg $wdr/$zpkg
    echo 'y' | download $zurl $zpkg
else
    download $zurl $zpkg
fi
zpkg=$(search $zpkg)
echo
echo "Archive '$zpkg' extraction"
echo
tar xvzf $zpkg -C . --strip-components=1

# Say goodbye and hand over
echo
let tms=($(date +%s%N)-$tms+500000000)/1000000000
echo "INFO: Preparation completed in $tms seconds"
if [ -n "$scrp" -a -n "$bdev" -a -r "$scrp" ]; then
    bash $scrp $iso $bdev $lang
else
    echo
fi

fi #############################################################################

