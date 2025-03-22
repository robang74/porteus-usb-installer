#!/bin/bash
#
# (C) 2025, Roberto A. Foglietta <roberto.foglietta@gmail.com> - 3-clause BSD
#
################################################################################
set -e

wdr=$(dirname "$0")
shs=$(basename "$0")
usage_strn="/path/file.iso [/dev/]sdx [it] [--ext4-install]"

# Comment this line below to have the journal within the persistence loop file
nojournal="-O ^has_journal"

# This below is the default size in 512-blocks for the persistent loop file
blocks="256K"

################################################################################

function isdevel() { test "$DEVEL" == "${1:-1}"; }
function perr() { { echo; echo "$@"; } >&2; }
function errexit() { echo; exit ${1:-1}; }

function usage() {
    perr "USAGE: bash ${shs:-$(basename $0)} $usage_strn"
    eval "$@"
}

function missing() {
    perr "ERROR: file '${1:-}' is missing, abort!"
    errexit
}

function sure() {
    local ans
    echo
    read -p "Are you sure to continue [N/y] " ans
    ans=${ans:0:1}
    test "$ans" == "Y" -o "$ans" == "y" && return 0
    errexit
}

function waitdev() {
    while false; do
        umount /dev/$dev* 2>/dev/null || true
        partprobe 2>&1 | grep -v "recursive partition" |\
            grep . || break
        sleep 0.5
    done
    partprobe; for i in $(seq 1 100); do
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

if [ "x$1" == "x-h" -o "x$1" == "x--help" ]; then ##############################
    usage echo
else ###########################################################################

trap "echo; echo; exit 1" INT

declare -i ext=0
iso=${1:-}
dev=${2:-}
if [ "x$3" == "x--ext4-install" ]; then
    ext=4
    shift
fi
kmp=${3:-}
ext=${4:+4}

sve="changes.dat"
bgi="moonwalker-background.jpg"
bsi="moonwalker-bootscreen.png"
opt="-E lazy_itable_init=1,lazy_journal_init=1 -F"
cfg="/boot/syslinux/porteus.cfg"
mbr="porteus-usb-bootable.mbr.gz"

# RAF, TODO: here is better to use mktemp, instead
#
lpd="/tmp/l"
dst="/tmp/d"
src="/tmp/s"

test -b "/dev/$dev" || dev=$(basename "$dev")
test -b "/dev/$dev" || usage errexit
test -r "$iso" || iso="$wdr/$iso"
test -r "$iso" || usage errexit

test -r "$bsi" || bsi="$wdr/$bsi"
test -f "$bsi" || bsi=""
test -r "$bgi" || bgi="$wdr/$bgi"
test -f "$bgi" || bgi=""

test -r "$mbr" || mbr="$wdr/$mbr"
test -r "$mbr" || missing "$mbr"
test -n "$kmp" && kmp="kmap=$kmp"

if [ "$(whoami)" != "root" ]; then
    perr "WARNING: script '$shs' for '/dev/$dev' requires root priviledges"
    echo
# RAF: this could be annoying but it could also be an extra safety checkpoint
    test "$DEVEL" == "1" ||  sudo -k
    sudo bash $0 "$@"
    exit $?
fi

################################################################################

perr "RUNNING: $shs $(basename "$iso") into /dev/$dev" ${kmp:+with $kmp} ext:$ext
fdisk -l /dev/${dev} >/dev/null || errexit
echo; fdisk -l /dev/${dev} | sed -e "s,^.*$,\t&,"
perr "WARNING: all data on '/dev/$dev' will be LOST"
sure

# Clear previous failed runs, eventually
umount ${src} ${dst} 2>/dev/null || true
umount /dev/${dev}* 2>/dev/null || true
echo
if mount | grep /dev/${dev}; then
    perr "ERROR: device /dev/${dev} is busy, abort!"
    errexit
fi
mkdir -p ${lpd} ${dst} ${src}
declare -i tms=$(date +%s%N)

# Write MBR and basic partition table
if false; then
    if [ $ext -eq 4 ]; then
        dd if=$(search $iso) bs=1M count=1 | if [ -n "$kmap" ]; then
            sed -e "s,# kmap=br,kmap=$kmp  ,"; else dd status=none; fi
    else
        zcat ${mbr}
    fi >/dev/${dev}
fi
zcat ${mbr} >/dev/${dev}
waitdev ${dev}1

# Prepare partitions and filesystems
if [ $ext -eq 4 ]; then
    printf "d_n____+16M_t_17_a_n_____w_" |\
        tr _ '\n' | fdisk /dev/${dev}
    waitdev ${dev}2
    mkfs.vfat -n EFIBOOT /dev/${dev}1
    mke4fs "Porteus" /dev/${dev}2
else
    mkfs.vfat -n Porteus /dev/${dev}1
    printf "n_p_2___w_" | tr _ '\n' |\
        fdisk /dev/${dev}; waitdev ${dev}2
    mke4fs "Portdata" /dev/${dev}2
fi

# Mount source and destination devices
echo
mkdir -p ${dst} ${src};
mount /dev/${dev}1 ${dst}
mount -o loop ${iso} ${src}

# Copying Porteus EFI/boot files from ISO file
cp -arf ${src}/boot ${src}/EFI ${dst}
test -r ${dst}/${cfg} || missing ${dst}/${cfg}
echo
str=" ${kmp}"; test $ext -eq 4 || str="/${sve} ${kmp}"
sed -e "s,APPEND changes=/porteus$,&${str}," -i ${dst}/${cfg}
grep -n  "APPEND changes=/porteus${str}" ${dst}/${cfg}
if test -n "${bsi}" && cp -f ${bsi} ${dst}/boot/syslinux/porteus.png; then
    perr "INFO: custom boot screen background '${bsi}' copied"
fi

# Creating persistence loop filesystem or umount
if [ $ext -eq 4 ]; then
    umount ${dst}
    mount /dev/${dev}2 ${dst}
else
    dd if=/dev/zero count=1 seek=${blocks} of=${sve}
    mke4fs "changes" ${sve} ${nojournal}
    mkdir -p ${dst}/porteus/
    mv -f ${sve} ${dst}/porteus/
    #sync ${dst}/*.txt &
fi

# Copying Porteus system and modules from ISO file
cp -arf ${src}/*.txt ${src}/porteus ${dst}
if test -n "${bsi}"; then
    lpd=${dst}/porteus/rootcopy
    mkdir -p ${lpd}/usr/share/wallpapers/
    cp ${bgi} ${lpd}/usr/share/wallpapers/porteus.jpg
    chmod a+r ${lpd}/usr/share/wallpapers/porteus.jpg
    perr "INFO: custom background '${bgi}' copied"
fi

# Umount source and eject USB device
perr "INFO: waiting for umount synchronisation..."
#wait
umount ${src}
umount ${dst}
fsck -yf /dev/${dev}2 || true
eject /dev/${dev}

# Say goodbye and exit
set +xe
echo
let tms=($(date +%s%N)-$tms+500000000)/1000000000
echo "INFO: Installation completed in $tms seconds"
echo
echo "DONE: bootable USB key ready to be removed safely"
echo

fi #############################################################################

