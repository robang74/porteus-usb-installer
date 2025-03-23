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

ddir="downloads"
echo $0 | grep -q /dev/fd/ &&\
    ddir="porteus.raf"

export download_path=${download_path:-$PWD/$ddir}
export workingd_path=$(dirname $(realpath "$0"))

usage_strn="[<type> <url> <arch> <vers>] [/dev/sdx] [it]"

function isdevel() { test "$DEVEL" == "${1:-1}"; }
function perr() { { echo; echo -e "$@"; } >&2; }
function errexit() { echo; exit ${1:-1}; }

function usage() {
    perr "USAGE: bash ${shs:-$(basename $0)} $usage_strn"
    eval "$@"
}

isdevel && perr "download path: $download_path\nworkingd path: $workingd_path"

################################################################################
if false; then errexit #////////////////////////////////////////////////////////

echo '#!/bin/bash
stat=$(head -c35 /proc/$PPID/stat)
pcmd=$(echo $(strings /proc/$PPID/cmdline))
echo 0:$0:$$ ppid:$PPID pcmd:$pcmd stat:$stat
' | tee test.sh | grep -v .; chmod a+x test.sh

cmd=$(echo $(strings /proc/$$/cmdline))
echo me cmd:$$:$cmd; bash -i <(cat test.sh)

# RAF: output from the code above to make properly work the code below
# me cmd:2170724:bash /dev/fd/63
# 0:/dev/fd/62:2170760 ppid:2170724 pcmd:bash /dev/fd/63
#                      stat:2170724 (bash) S 1786462 2170724 17

tagver="v0.2.8" # To replace with the lastest available in tags
rawurl="https://raw.githubusercontent.com/robang74"
rawurl="$rawurl/porteus-usb-installer/refs/tags/$tagver"
rawurl="$rawurl/porteus-net-install.sh"
DEVEL=0 # bash -i <(wget -qO- $net_inst_url)

fi #\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
################################################################################
# set -x
if [ "x$1" == "x-h" -o "x$1" == "x--help" ]; then # RAF: isn't a kind of magic!?
    usage echo
elif [ "$download_path" == "$workingd_path" ]; then # Avoid to over-write myself
    d="$download_path/tmp"; mkdir -p "$d"; cp -f "$0" "$d/$shs"
    exec bash "$d/$shs" "$@"   # exec replaces this process, no return from here
    perr "ERROR: exec fails or a bug hits here, abort!"; errexit -1 # eventually
else
    mkdir -p "$download_path"
    pushd "$download_path" >/dev/null
    perr "-> pwd: $PWD"
# set +x
################################################################################

# This values depend by external sources and [TODO] should be shared here
mirror_file=${mirror_file:-porteus-mirror-selected.txt}
mirror_dflt=${mirror_dflt:-https://mirrors.dotsrc.org}
sha256_file=${sha256_file:-sha256sums.txt}

# Script package to download and script name to execute
rver="v0.2.8"
zpkg="$rver.tar.gz"
repo="https://github.com/robang74/porteus-usb-installer"
rawu="https://raw.githubusercontent.com/robang74/porteus-usb-installer/"
mirrors_script_name="porteus-mirror-selection.sh"
usbinst_script_name="porteus-usb-install.sh"
zpkg_url="$repo/archive/refs/tags"
rawc_url="$rawu/refs/tags/$rver"

################################################################################

function missing() {
    perr "ERROR: file '${1:-}' is missing, abort!"
    errexit
}

function unsure() {
    local ans
    echo; read -p "${1:-Are you sure to continue}? [N/y] " ans
    ans=${ans^^}; test "${ans:0:1}" == "Y" || return 1
}

function agree() {
    local ans
    echo; read -p "${1:-Are you sure to continue}? [Y/n] " ans
    ans=${ans^^}; test "${ans:0:1}" != "N" || return 1
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
        agree "${sure_string}" || errexit
        if ! wget -q --show-progress $opt $url/$f; then
            perr "ERROR: downloading '$f', abort!"
            errexit
        fi
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
   zpkg_url="$repo/archive/refs/heads"
   rawc_url="$repo/refs/heads/main"
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
    agree "Do you want to check for the fastest mirror available" || break
    fname=${mirrors_script_name}
    script=$(search $fname ||:)
    if [ ! -r "$script" ]; then
        perr "WARNING: the script '$fname' is missng"
        sure_string="Do you want to download it from github" \
            download ${rawc_url} $fname
        script=$(search $fname || missing $fname)
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

prt=; test "$(basename $uweb)" == "porteus" || prt="porteus"
url=$(echo "$uweb/$prt/$arch/$vers" | sed -e "s,http:,https:,")

################################################################################

declare -i tms=$(date +%s%N)

download $url $sha256_file
shf=$(search $sha256_file)
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
    echo 'y' | download ${zpkg_url} $zpkg
else
    download ${zpkg_url} $zpkg
fi
zpkg=$(search $zpkg)
echo
echo "Archive '$zpkg' extraction"
echo
tar xvzf $zpkg -C . --strip-components=1

# Say goodbye and hand over, eventually
echo
let tms=($(date +%s%N)-$tms+500000000)/1000000000
echo "INFO: Preparation completed in $tms seconds"
echo
echo ">>>>  Directory '$ddir' populated: $(du -ms . | tr -cd [0-9]) MB"
scrp=${usbinst_script_name}
if [ -n "$scrp" -a -n "$bdev" -a -r "$scrp" ]; then
    bash $scrp $iso $bdev $lang
else
    echo
fi

fi #############################################################################

