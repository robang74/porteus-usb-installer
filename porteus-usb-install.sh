#!/bin/bash
#
# (C) 2025, Roberto A. Foglietta <roberto.foglietta@gmail.com> - 3-clause BSD
#
################################################################################
set -e

USAGE="/path/file.iso [/dev/]sdx [it] [--ext4-install]"

# Comment this line below to have the journal within the persistence loop file
nojournal="-O ^has_journal"

# This below is the default size in 512-blocks for the persistent loop file
blocks="256K"

################################################################################

function errexit() { echo; exit 1; }

function perr() {
    { echo; echo "$@"; } >&2
}

function usage() {
    perr "USAGE: bash $shs $USAGE"
    errexit
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

################################################################################

wdr=$(dirname "$0")
shs=$(basename "$0")

if [ "x$1" == "x-h" -o "x$1" == "x--help" ]; then
    usage
    echo
    exit
fi

################################################################################

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
test -b "/dev/$dev" || usage
test -r "$iso" || iso="$wdr/$iso"
test -r "$iso" || usage

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
#   sudo -k
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
umount /dev/${dev}? 2>/dev/null || true
echo
if mount | grep /dev/${dev}; then
    perr "ERROR: device /dev/${dev} is busy, abort!"
    errexit
fi
mkdir -p ${lpd} ${dst} ${src}
declare -i tms=$(date +%s%N)

# Write MBR and basic partition table
if [ $ext -eq 4 ]; then
    dd if=$(search $iso) bs=1M count=1 | if [ -n "$kmap" ]; then
        sed -e "s,# kmap=br,kmap=$kmp  ,"; else dd; fi
else
    zcat ${mbr}
fi >/dev/${dev}
waitdev ${dev}1
#fisk -l /dev/${dev}

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
mkdir -p ${dst} ${src};
mount /dev/${dev}1 ${dst}
mount -o loop ${iso} ${src}

# Copying Porteus files from ISO file
cp -arf ${src}/boot ${src}/EFI ${dst}
test -r ${dst}${cfg} || missing ${dst}${cfg}
if test -n "${bsi}" && cp -f ${bsi} ${dst}/boot/syslinux/porteus.png;
   then echo "INFO: custom boot screen background '${bsi}' copied"; fi
sed -e "s,APPEND changes=/porteus$,&/${sve} ${kmp}," -i ${dst}${cfg}
if [ $ext -eq 4 ]; then
    umount ${dst}
    mount /dev/${dev}2 ${dst}
else
    grep -n "changes=/porteus/${sve}" ${dst}${cfg}
fi
cp -arf ${src}/*.txt ${src}/porteus ${dst}
sync -f ${dst}/*.txt &

# Creating persistence loop filesystem
if [ $ext -eq 4 ]; then
    lpd=${dst}/porteus/changes
else
    dd if=/dev/zero count=1 seek=${blocks} of=${sve}
    mke4fs "changes" ${sve} ${nojournal}
fi
if test -n "${bsi}"; then
    test $ext -eq 4 || mount -o loop ${sve} ${lpd}
    mkdir -p ${lpd}/usr/share/wallpapers/
    cp ${bgi} ${lpd}/usr/share/wallpapers/porteus.jpg
    chmod a+r ${lpd}/usr/share/wallpapers/porteus.jpg
    echo "INFO: custom background '${bgi}' copied"
    test $ext -eq 4 || umount ${lpd}
fi

# Moving persistence and configure it
perr "INFO: waiting for fsdata synchronisation..."
wait
test $ext -eq 4 || mv -f ${sve} ${dst}/porteus/

# Umount source and eject USB device
perr "INFO: waiting for umount synchronisation..."
umount ${src} ${dst}
eject /dev/${dev}
set +xe

# Say goodbye and exit
echo
let tms=($(date +%s%N)-$tms+500000000)/1000000000
echo "INFO: Installation completed in $tms seconds"
echo
echo "DONE: bootable USB key ready to be removed safely"
echo
