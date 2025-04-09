#!/bin/bash
#
# (C) 2025, Roberto A. Foglietta <roberto.foglietta@gmail.com> - 3-clause BSD
#
################################################################################
set +o noclobber
set +u
set -e

#d=/media/roberto/porteus/porteus

d=$(df -h | grep -i porteus | tr -s ' ' | cut -d' ' -f6 | head -n1)
d=$d/porteus
echo
for i in $d/base/* $d/modules/*; do
    str=$(file $i | sed -e "s,.* created: \(.*\),\\1," -e "s,[^ ]\+ \+\([^ ]\+\) \+\([^ ]\+\) [^ ]\+ \([0-9]\+\),\\3 \\1 \\2," -e "s,Jan,01," -e "s,Feb,02," -e "s,Mar,03," -e "s,Apr,04," -e "s,May,05," -e "s,Jun,06," -e "s,Jul,07," -e "s,Aug,08," -e "s,Sep,09," -e "s,Oct,10," -e "s,Nov,11," -e "s,Dec,12,")
    printf "%s\t%d%s%02d-%s\n" "$(dirname $i)" $str "$(basename $i)"
done | sort -k2 -rn
echo
