#!/bin/bash
#
# (C) 2025, Roberto A. Foglietta <roberto.foglietta@gmail.com> - 3-clause BSD
#
################################################################################
set -e

wdr=$(dirname "$0")
shs=$(basename "$0")
usage_strn="[--clean]"

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

function rm_wget_log() { rm -f ??-$wgetlogtail; }
function pn_wget_log() { printf "%02d-$wgetlogtail" $1; }

if [ "x$1" == "x-h" -o "x$1" == "x--help" ]; then ##############################
    usage echo
elif [ "x$1" == "x--clean" ]; then #############################################
    rm_wget_log; rm -f $mirror_file $wgetlogtail; printf "\ndone.\n\n"
else ###########################################################################

trap "echo; echo; exit 1" INT

list=$(wget -qO- https://porteus.org/porteus-mirrors.html |\
    sed -ne 's,.*<a href="\([^"]*\)".*,\1,p')

domlst=$(echo "$list" | cut -d/ -f3)

echo
printf "Sending one ping to all the mirrors, DNS caching ... "
for i in $domlst; do
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
        printf "%02d: $i\n" $n | tee $fn
        wget -O- $i/$arch/$vers/$dtst >/dev/null 2>> $fn && wlst="$wlst
$i"
    done
fi

topl=$(grep written *$wgetlogtail | sed -e "s,:.*(\(.*\)).*,: \\1," | tr -d . |\
    sed -e "s, MB/s,0 KB/s,"  | sort -rnk 2)
winr=$(echo "$topl" | head -n1)
wfln=$(echo "$winr" | cut -d: -f1)
strn=$(head -n1 $wfln | cut -d' ' -f2)
winr=$(echo "$winr" | sed -e "s,-$wgetlogtail,,")
echo
echo "$topl"
echo
echo "Fastest --> $strn <-- $winr"
echo

echo $strn | cut -d' ' -f2 > $mirror_file
for i in $(ls -1 *$wgetlogtail); do
    cat $i; printf "===\n\n"
done > $netlog_file
isdevel 0 && rm_wget_log
echo "Saved into '$mirror_file' file"
echo "created '$netlog_file' file"
echo

fi #############################################################################

