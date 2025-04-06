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
usage_strn=""

export DEVEL=${DEVEL:-0}

# RAF: these values depend by external sources and [TODO] should be shared #____

export porteus_type=${porteus_type:-MATE}
export porteus_arch=${porteus_arch:-x86_64}
export porteus_version=${porteus_version:-Porteus-v5.1} #current

## RAF: defined by `mirror-selection` script
export sha256_file=${sha256_file:-sha256sums.txt}
export mirror_file=${mirror_file:-porteus-mirror-selected.txt}
export mirror_dflt=${mirror_dflt:-https://mirrors.dotsrc.org/porteus}

# RAF: internal values #________________________________________________________

backup_version="Porteus-v5.01"
bundles_dir="bundles"

# RAF: basic common functions #_________________________________________________

function is_menu_mode() { grep -q -- "--user-menu" /proc/$$/cmdline; }
function asking_help() { grep -qe "help" -e "\-h" /proc/$$/cmdline; }
function is_on_demand() { echo "$0" | grep -q "/dev/fd/"; }
function isdevel() { test "${DEVEL:-0}" != "0"; }
function perr() { { printf "$@"; } >&2; }
function errexit() { echo; exit ${1:-1}; }
function tabout() { sed -e 's,^.,    &,'; }

function amiroot() {
    test "$EUID" == "0" -o "$ID" == "0" -o "$(whoami)" == "root"
}

function usage() {
    printf \\n"USAGE: bash ${shs:-$(basename $0)} $usage_strn"\\n
    eval "$@"
}

function search() {
    local d ldirs=". $wdr $workingd_path .." f="${1:-}"
    test -n "$f" || return 1
    test "$(basename $wdr)"  == "tmp" && ldirs="$ldirs .."
    for d in $ldirs; do
        if [ -d "$d" -a -r $d/$f ]; then echo "$d/$f"; return 0; fi
    done; return 1
}

# RAF: basic common check & set #_______________________________________________

if is_on_demand; then
    wdr=$PWD
    perr \\n"###############################################"
    perr \\n"This is an on-demand from remote running script"
    perr \\n"###############################################"\\n\\n
else
    test -n "$wdr" && wdr=$(realpath $wdr)
fi

workingd_path=$(dirname $(realpath "$0"))
download_path=${download_path:-$PWD}
if [ "$(basename $PWD)" != "$store_dirn" ]; then
    download_path="$download_path/$store_dirn"
fi

v="-q --show-progress"
s=$bundles_dir.${sha256_file/.txt/}
m=$(cat $mirror_file 2>/dev/null ||:)
m=${m:-$mirror_dflt}

# RAF: internal check & set and early functions #_______________________________

printf \\n"INFO: active mirror '$m'"\\n

u1=$m/${porteus_arch}/${porteus_version}/${bundles_dir}
u2=$m/${porteus_arch}/${backup_version}/${bundles_dir}

while true; do #################################################################

if [ "$(basename $PWD)" != "$store_dirn" ]; then
    test -d $store_dirn && cd $store_dirn
    chd=1
fi

printf \\n"INFO: downloading the $sha256_file ... "
for u in "$u1" "$u2" ""; do
    test -n "$u" || break
    wget -qO- $u/$sha256_file > $s && break
done; echo "done."

if [ ! -n "$u" ]; then
    perr "ERROR: the '$bundles_dir' not found, abort!"
    break
fi

printf \\n"INFO: downloading, wait ..."\\n\\n
for i in "man-lite" "netsurf" "remmina"; do
    f=$(grep $i $s | tr -s ' ' | cut -d ' ' -f2 | sort -n | tail -n1)
    test -r $f || wget $v -c $u/$f 
    sha256sum -c $s 2>/dev/null | grep OK | grep $i | tabout
done
echo

test "$chd" == "1" && cd - >/dev/null

break; done ####################################################################

