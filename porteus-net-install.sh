#!/bin/bash
#
# (C) 2025, Roberto A. Foglietta <roberto.foglietta@gmail.com> - 3-clause BSD
#
################################################################################
set -e

ddir="downloads"
wdr=$(dirname "$0")
shs=$(basename "$0")

export download_path=${download_path:-$PWD/$ddir}
export workingd_path=$(dirname $(realpath "$0"))

usage_strn="[<type> <url> <arch> <vers>] [/dev/sdx] [it]"

function isdevel() { test "$DEVEL" == "${1:-1}"; }
function perr() { { echo; echo "$@"; } >&2; }
function errexit() { echo; exit ${1:-1}; }

function usage() {
    perr "USAGE: bash ${shs:-$(basename $0)} $usage_strn"
    eval "$@"
}

perr "download path: $download_path
workingd path: $workingd_path"

################################################################################

# echo '#!/bin/bash
# stat=$(head -c35 /proc/$PPID/stat)
# pcmd=$(echo $(strings /proc/$PPID/cmdline))
# echo 0:$0:$$ ppid:$PPID pcmd:$pcmd stat:$stat
# ' | tee test.sh | grep -v .; chmod a+x test.sh
# cmd=$(echo $(strings /proc/$$/cmdline))
# echo me cmd:$$:$cmd; cat test.sh | bash
# bash test.sh; ./test.sh; source test.sh

# me cmd:1786462:bash
# 0:bash:2119399 ppid:1786462 pcmd:bash stat:1786462 (bash) S 11361 1786462 1786
# 0:test.sh:2119403 ppid:1786462 pcmd:bash stat:1786462 (bash) S 11361 1786462 1786
# 0:./test.sh:2119407 ppid:1786462 pcmd:bash stat:1786462 (bash) S 11361 1786462 1786
# 0:bash:1786462 ppid:11361 pcmd:/usr/libexec/gnome-terminal-server stat:11361 (gnome-terminal-) R 10402 113

set -x
################################################################################
if [ "x$1" == "x-h" -o "x$1" == "x--help" ]; then # RAF: isn't a kind of magic!?
    usage echo
elif [ "$download_path" == "$workingd_path" ]; then # Avoid to over-write myself
    td="$download_path/tmp/"; mkdir -p "$td"; cp -f "$0" "$td/$shs"; pushd "$td"
    bash $shs "$@" || exit $? && exit 0 & # busybox ash & may need explicit exit
else #### Logic switches keep the line atomic, while goes in background with '&'
fg 2>/dev/null || : # The fork above joins here for the sake of user interaction
################################################################################
set +x

# This values depend by external sources and [TODO] should be shared here
mirror_file=${mirror_file:-porteus-mirror-selected.txt}
mirror_dflt=${mirror_dflt:-https://mirrors.dotsrc.org}
sha256_file=${sha256_file:-sha256sums.txt}

# Script package to download and script name to execute
zpkg="v0.2.8.tar.gz"
repo="https://github.com/robang74/porteus-usb-installer"
zurl="$repo/archive/refs/tags"
scrp="porteus-usb-install.sh"

################################################################################

function missing() {
    perr "ERROR: file '${1:-}' is missing, abort!"
    errexit
}

function sure() {
    local ans
    echo; read -p "${1:-Are you sure to continue}? [N/y] " ans
    ans=${ans^^}; test "${ans:0:1}" == "Y" || return 1
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
        sure || errexit
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

################################################################################

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

# RAF: while true w/break avoid nesting too much and avoid the use of exit
#      avoiding explicit exit, is a good idea when `source` a `set -e` .sh.
while true; do
    test -n "$2" -o -r $mirror_file && break
    perr "WARNING: no any mirror selected, using '$mirror_dflt'"
    sure "Do you want to check for the fastest mirror available" || break
    script=$(search porteus-mirror-selection.sh)
    if [ ! -r "$script" ]; then
        perr "WARNING: the script '$script' is missng"
        sure "Do you want to download it from github" || break
        script=$(search porteus-mirror-selection.sh)
    fi
    bash $script
    break
done

type=${1^^}
type=${type:-MATE}
uweb=${2:-$(cat $mirror_file 2>/dev/null ||:)}
uweb=${uweb:-$mirror_dflt}
arch=${3:-x86_64}
vers=${4:-current}
bdev=$5
lang=$6

shf=$sha256_file
url="$uweb/porteus/$arch/$vers"

################################################################################

if [ "$(basename $PWD)" != "$ddir" ]; then
    mkdir -p $ddir; pushd $ddir
fi
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

