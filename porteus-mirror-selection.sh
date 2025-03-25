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
usage_strn="[--clean]"

export DEVEL=${DEVEL:-0}

# RAF: these values depend by external sources and [TODO] should be shared #____

export sha256_file="sha256sums.txt"
export mirror_file="porteus-mirror-selected.txt"

# RAF: internal values #________________________________________________________

mirror_list="porteus-mirror-allhttps.txt"
netlog_file="porteus-mirror-selected.log"
wgetlogtail="wget-log"

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

function search() {
    local d ldirs=". $wdr" f="${1:-}"
    test -n "$f" || return 1
    test "$(basename $wdr)"  == "tmp" && ldirs="$ldirs .."
    for d in $ldirs; do
        if [ -d "$d" -a -r $d/$f ]; then echo "$d/$f"; return 0; fi
    done; return 1
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

function pn_wget_log() { printf "%02d-$wgetlogtail" $1; }
function wgetlogs_ls() { command ls -1 ??-$wgetlogtail 2>/dev/null ||:; }
function rm_wget_log() { rm -f $(wgetlogs_ls) *.discarded ??-$sha256_file; }

################################################################################
if askinghelp; then usage errexit 0;
elif [ "x$1" == "x--clean" ]; then #############################################
    rm_wget_log; rm -f $mirror_file $netlog_file; printf "\ndone.\n\n"
else ###########################################################################

trap "echo; echo; exit 1" INT

perr "-> pwd: $PWD"

list=$(wget -qO- https://porteus.org/porteus-mirrors.html |\
    sed -ne 's,.*<a href="\([^"]*\)".*,\1,p')
list="$(cat $mirror_list 2>/dev/null ||:)
$list"
list=$(echo "$list" | sed -e "s,http:,https:," | sort | uniq)
echo "$list" >$mirror_list

echo
printf "Sending one ping to all the mirrors, DNS caching ... "
for i in $(echo "$list" | cut -d/ -f3); do
    ping -w1 -W1 -c 1 -q $i &
done >/dev/null 2>&1
echo "done"

wlst=
arch=x86_64
vers=current
dtst=bundles/man-lite-porteus-20220607-x86_64-alldesktops.xzm

printf "\nDownload speed testing for every mirror, wait.\n"
echo; # set -x # RAF, TODO: this part is still working in progress... (WIP!!)
declare -i n=0 errf=0
for i in $list STOP; do
    if [ $errf -gt 0 ]; then
        mv $fn $fn.discarded
        printf "\tdiscarded\n"
    fi
    test "$i" == "STOP" || break
    let n++ ||:; errf=1
    fn=$(pn_wget_log $n)
    url=$i/$arch/$vers
    printf "%02d: $i\n" $n | tee $fn
    wget --timeout=5 -O- >/dev/null $url/$dtst 2>>$fn || continue
    svf=$(printf "%02d" $n)-$sha256_file
    wget --timeout=5 -qO- $url/$sha256_file >$svf || continue
    grep -i porteus $svf || continue
    wlst="$wlst $i"
    errf=0
done; # set +x

# RAF: an alternative using dd which can be leveraged to cap the download size
# wget --timeout=1 -qO- $url | dd bs=1500 count=5k iflag=fullblock of=/dev/null\
#   2>&1 | sed -ne "/bytes/s/.* s, \(.*\)/\\1/p" | tr [gmk] [GMK]

topl=$(grep "written" $(wgetlogs_ls) /dev/null|\
    sed -e "s,:.*(\(.*\)).*,: \\1," | tr -d . |\
    sed -e "s, MB/s,0 KB/s," | sort -rnk 2)
winr=$(echo "$topl" | head -n1)
wfln=$(echo "$winr" | cut -d: -f1)
strn=$(head -n1 "$wfln" | cut -d' ' -f2)
winr=$(echo "$winr" | sed -e "s,-$wgetlogtail,,")
echo
echo "$topl"
echo
echo "Fastest --> $strn <-- $winr"
echo

echo $strn | cut -d' ' -f2 > $mirror_file
for i in $(wgetlogs_ls); do
    cat $i; printf "===\n\n"
done > $netlog_file; #rm_wget_log
echo "updated '$mirror_file' file"
echo "updated '$mirror_list' file"
echo "created '$netlog_file' file"
echo

fi #############################################################################

