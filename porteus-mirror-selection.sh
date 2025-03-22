#!/bin/bash
#
# (C) 2025, Roberto A. Foglietta <roberto.foglietta@gmail.com> - 3-clause BSD
#
################################################################################
set -e

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

printf "\nDownload speed testing for every mirror, wait.\n\n"
for i in $list; do
    let n++ ||:
    fn=$(printf "%02d-wget-log" $n)
    printf "%02d: $i\n" $n | tee $fn
    wget -O- $i/$arch/$vers/$dtst >/dev/null 2>> $fn && wlst="$wlst
$i"
done

topl=$(grep written *wget-log | sed -e "s,:.*(\(.*\)).*,: \\1," | tr -d . |\
    sed -e "s, MB/s,0 KB/s,"  | sort -rnk 2)
winr=$(echo "$topl" | head -n1)
wfln=$(echo "$winr" | cut -d: -f1)
strn=$(head -n1 $wfln)
echo
echo "$topl"
echo
echo "Fastest --> $winr --> "$strn
echo

echo $strn | cut -d' ' -f2 > porteus-mirror-selected.txt
for i in $(ls -1 *wget-log); do
    cat $i; printf "===\n\n"
done > porteus-mirror-selected.log; rm -f *wget-log
echo "Saved into 'porteus-mirror-selected.txt' file"
echo "created 'porteus-mirror-selected.log' file"
echo

