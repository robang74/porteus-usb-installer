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
dir=$PWD

mir="porteus-mirror-selection.sh"
net="porteus-net-install.sh"
store_dirn="moonwalker"

echo
echo "launch dir: $dir"
if [ -d "$store_dirn" ]; then
    cd "$store_dirn"
fi
cln=$PWD
echo "clean  dir: $cln"
echo
for f in $mir $net; do
    for d in . $dir $wdr ..; do
        if [ -r $d/$f ]; then
            printf "$f --clean: "
            bash $d/$f --clean 2>&1 | grep "done" ||:
            last=$f
            break
        fi
    done
done
test "$last" == "$net" && echo "done."
cd .
list=$(ls -1)
if [ -n "$list" ]; then
    printf "\nfiles left untouched in $(basename $cln)/:\n\n"
    echo "$list" | sed -e "s/.*/    &/"
fi
echo
