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
usage_strn="[--clean]"

mirror_list="porteus-mirror-allhttps.txt"
mirror_file="porteus-mirror-selected.txt"
netlog_file="porteus-mirror-selected.log"
wgetlogtail="wget-log"

function isdevel() { test "$DEVEL" == "${1:-1}"; }
function perr() { { echo; echo "$@"; } >&2; }
function errexit() { echo; exit ${1:-1}; }

function usage() {
    perr "USAGE: bash ${shs:-$(basename $0)} $usage_strn"
    eval "$@"
}

function rm_wget_log() { rm -f $(wgetlogs_ls); }
function pn_wget_log() { printf "%02d-$wgetlogtail" $1; }
function wgetlogs_ls() { command ls -1 ??-$wgetlogtail; }

if [ "x$1" == "x-h" -o "x$1" == "x--help" ]; then ##############################
    usage echo
elif [ "x$1" == "x--clean" ]; then #############################################
    rm_wget_log; rm -f $mirror_file $netlog_file; printf "\ndone.\n\n"
else ###########################################################################

trap "echo; echo; exit 1" INT

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
declare -i n=0

printf "\nDownload speed testing for every mirror, wait.\n"
if ! isdevel; then
    echo
    for i in $list; do
        let n++ ||:
        fn=$(pn_wget_log $n)
        url=$i/$arch/$vers/$dtst
        printf "%02d: $i\n" $n | tee $fn
        wget --timeout=1 -O- >/dev/null $url 2>>$fn && wlst="$wlst
$i"
    done
fi

# RAF: an alternative using dd which can be leveraged to cap the download size
# wget --timeout=1 -qO- $url | dd bs=1500 count=5k iflag=fullblock of=/dev/null\
#   2>&1 | sed -ne "/bytes/s/.* s, \(.*\)/\\1/p" | tr [gmk] [GMK]

topl=$(grep "written" $(wgetlogs_ls)|\
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

