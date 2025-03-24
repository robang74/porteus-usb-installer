#!/bin/bash
#
# (C) 2025, Roberto A. Foglietta <roberto.foglietta@gmail.com> - 3-clause BSD
#
# Support for expert users wishing to test on-demand installation starts from
#
# URL: https://raw.githubusercontent.com/robang74/porteus-usb-installer
# VER:                         /refs/tags/v0.3.1/porteus-net-install.sh
# MAN:                           ?tab=readme-ov-file#usage-quick--dirty
#
# It is suggest testing on a spare machine that does NOT hold valuable data,
# possibly using a Porteus MATE v5.0.1 with the network support available.
#
################################################################################
set +o noclobber
set +u
set -e

store_dirn="moonwalker"
usage_strn="[<type> <url> <arch> <vers>] [/dev/sdx] [it]"

wdr=$(dirname "$0")
shs=$(basename "$0")

# This values depend by external sources and [TODO] should be shared here

export workingd_path=$(dirname $(realpath "$0"))
export download_path=${download_path:-$PWD/$store_dirn}
export mirror_file=${mirror_file:-porteus-mirror-selected.txt}
export mirror_dflt=${mirror_dflt:-https://mirrors.dotsrc.org}
export sha256_file=${sha256_file:-sha256sums.txt}

function isondemand() { echo "$0" | grep -q "/dev/fd/"; }
function isdevel() { test "$DEVEL" == "${1:-1}"; }
function perr() { { echo; echo -e "$@"; } >&2; }
function errexit() { echo; exit ${1:-1}; }

function amiroot() {
    test "$EUID" == "0" -o "$ID" == "0" -o "$(whoami)" == "root"
}

function usage() {
    perr "USAGE: bash ${shs:-$(basename $0)} $usage_strn"
    eval "$@"
}

if isdevel; then
    perr "download path: $download_path\nworkingd path: $workingd_path"
else
    # RAF: this could be annoying for DEVs but is an extra safety USR checkpoint
    sudo -k
fi

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

tagver="v0.3.1" # To replace with the lastest available in tags
rawurl="https://raw.githubusercontent.com/robang74"
rawurl="$rawurl/porteus-usb-installer/refs/tags/$tagver"
rawurl="$rawurl/porteus-net-install.sh"
DEVEL=0 # bash -i <(wget -qO- $net_inst_url)

fi #\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
################################################################################
# set -x
if [ "x$1" == "x--clean" ]; then
    d=$download_path
    if [ ! -d "$d" ]; then
        perr "ERROR: folder '$d' does not exit, abort!"
        errexit
    fi
    if amiroot; then
        if [ ! -n "${SUDO_USER}" ]; then
            perr "ERROR: try as user, variable \$SUDO_USER is void/unset, abort!"
            errexit
        fi
        perr "WARNING: please execute this script as user, not as root"
        chown -R ${SUDO_USER}.${SUDO_USER} $d
        errexit
    fi
    while true; do
        # RAF: better use mktemp here
        rd="$d.$RANDOM"
        test -d $rd || break
        sleep 0.1
    done
    mkdir $rd && mv -f $d/*.iso $d/*.ISO $rd 2>/dev/null ||:\
         && rm -rf $d && mv $rd $d
    isolist=$(ls -1t $d/*.iso $d/*.ISO 2>/dev/null ||:)
    if [ -n "$isolist" ]; then
        perr "WARNING: the ISO image files are left untouched, do it manually"
    else
        perr "done."
    fi
    errexit 0
elif [ "x$1" == "x-h" -o "x$1" == "x--help" ]; then # RAF: isn't a kind of magic!?
    usage echo
elif amiroot; then
    perr "This script is NOT supposed being executed by root, abort!"
    errexit
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

function missing() {
    perr "ERROR: file '${1:-}' is missing, abort!"
    errexit
}

function besure() {
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
        agree "${sure_string}" || return 0 # user decided, and it is fine
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

function wget_last_tag() {
    wget -qO - "$1/tags" | sed -ne "s,.*/refs/tags/\(.*\)\.zip.*,\\1,p"|\
        sort -rn | head -n1 | grep .
}

################################################################################

if isondemand; then
    perr "###############################################"
    perr "This is an on-demand from remote running script"
    perr "###############################################"
fi

# Deciding which version download from the repo

user="robang74"
proj="porteus-usb-installer"
repo="https://github.com/$user/$proj"
rawu="https://raw.githubusercontent.com/$user/$proj"

tagver="v0.3.1"
reftyp="tags"

str="script suggests '$tagver' as last tagged, check for updates"
if isdevel; then
   tagver="main"
   reftyp="heads"
elif agree "WARNING: $str"; then
    tagnew=$(wget_last_tag $repo)
    if [ -n "$tagnew" ]; then
        tagver=$tagnew
        perr "-> tag: $tagver"
    else
        perr "WARNING: updates check failed, going with '$tagver' as default"
    fi
fi

# Script package to download and script names to execute

zpkg="$tagver.tar.gz"
zpkg_url="$repo/archive/refs/$reftyp"
rawc_url="$rawu/refs/$reftyp/$tagver"

mirrors_script_name="porteus-mirror-selection.sh"
usbinst_script_name="porteus-usb-install.sh"

################################################################################

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
    bash $script && echo "done."
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
download ${zpkg_url} $zpkg

zpkg=$(search $zpkg ||:)
if [ -r "$zpkg" ]; then
    echo
    echo "Archive '$zpkg' extraction"
    echo
    tar xvzf $zpkg -C . --strip-components=1
fi

# Say goodbye and hand over, eventually
echo
let tms=($(date +%s%N)-$tms+500000000)/1000000000
echo "INFO: Preparation completed in $tms seconds"

uis=${usbinst_script_name}
dsd=${store_dirn}
echo
echo "->  Directory '$dsd' populated: $(du -ms . | tr -cd [0-9]) MB"
if isondemand; then
    perr "###############################################"
    perr " Now you can insert the USB stick to be writen "
    perr "###############################################"
    if besure; then
        bash $uis --user-menu
    else
        bash $uis --help
    fi
elif [ -r "$uis" -a -n "$bdev" ]; then
    bash $uis $iso $bdev $lang
else
    echo
fi

fi #############################################################################

