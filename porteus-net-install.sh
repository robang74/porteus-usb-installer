#!/bin/bash
#
# (C) 2025, Roberto A. Foglietta <roberto.foglietta@gmail.com> - 3-clause BSD
#
################################################################################
set -e

# Script package to download and script name to execute
zpkg="v0.2.6.tar.gz"
repo="https://github.com/robang74/porteus-usb-installer"
zurl="$repo/archive/refs/tags"
scrp="porteus-usb-install.sh"

################################################################################

function perr() {
    { echo; echo "$@"; } >&2
}

function usage() {
    perr "USAGE: bash $shs /path/file.iso [/dev/]sdx [it]"
    exit 1
}

function missing() {
    perr "ERROR: file '${1:-}' is missing, abort!"
    exit 1
}

function sure() {
    local ans
    echo
    read -p "Are you sure to continue [N/y] " ans
    echo
    test "$ans" == "Y" -o "$ans" == "y" && return 0
    exit 1 
}

function waitdev() {
    partprobe
    for i in $(seq 1 100); do
        egrep " $1$" /proc/partitions && return 0
        sleep 0.1
    done
    perr "ERROR: waitdev('$1') failed, abort!"
    exit 1
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
        wget -q --show-progress $opt $url/$f || exit 1
    done
}

function isocheck() {
    printf "\nChecking '$1' sha256sum ... "
    if sha256sum $1 | grep -qw "$2"; then
        printf "OK\n\n"
    else
        printf "KO\n\n"
        return 1
    fi
}

wdr=$(dirname $0)
shs=$(basename $0)

################################################################################

trap "echo;echo;exit 1" INT
test -b $1 && set -- "" "" "" "" "$@"

type=${1:-MATE}
#uweb=${2:-https://linux.rz.rub.de}
uweb=${2:-https://mirrors.dotsrc.org}
arch=${3:-x86_64}
vers=${4:-current}
bdev=$5
lang=$6
shf="sha256sums.txt"
url="$uweb/porteus/$arch/$vers"

set +x
mkdir -p porteus; pushd porteus

download $url $shf
shf=$(search $shf)
chk=$(grep -ie "porteus.*-${type}-.*.iso" $shf | cut -d' ' -f1)
iso=$(grep -ie "porteus.*-${type}-.*.iso" $shf | tr -s ' ' | cut -d' ' -f2)

iso=$(search $iso)
if ! isocheck $iso $chk; then
    download -c $url $iso
    iso=$(search $iso)
    if ! isocheck  $iso $chk; then
        rm -f $iso
        exit 1
    fi
fi

download $zurl $zpkg
zpkg=$(search $zpkg)
tar xvzf $zpkg -C . --strip-components=1

test -n "$scrp" || exit 0
test -n "$bdev" || exit 0
test -r "$scrp" && bash $scrp $iso $bdev $lang

