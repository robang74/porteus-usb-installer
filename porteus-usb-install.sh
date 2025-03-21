#!/bin/bash
#
# (C) 2025, Roberto A. Foglietta <roberto.foglietta@gmail.com> - 3-clause BSD
#
################################################################################
set -e

# Comment this line below to have the journal within the persistence loop file
journal="-O ^has_journal"

# This below is the default size in 512-blocks for the persistent loop file
blocks="256K"

################################################################################

function perr() {
    { echo; echo "$@"; } >&2
}

function usage() {
    perr "USAGE: bash $shs /path/file.iso [/dev/]sdx [it]"
    echo
    exit 1
}

function missing() {
    perr "ERROR: file '${1:-}' is missing, abort!"
    echo
    exit 1
}

function sure() {
    local ans
    echo
    read -p "Are you sure to continue [N/y] " ans
    echo
    test "$ans" == "Y" -o "$ans" == "y" && return 0
    exit 1 
}

function waitdev() {
    partprobe
    for i in $(seq 1 100); do
        egrep " $1$" /proc/partitions && return 0
        sleep 0.1
    done
    perr "ERROR: waitdev('$1') failed, abort!"
    echo
    exit 1
}

function mke4fs() {
    local lbl=$1 dev=$2; shift 2
    mkfs.ext4 -L $lbl -E lazy_itable_init=1,lazy_journal_init=1 -F $dev "$@"
}

wdr=$(dirname "$0")
shs=$(basename "$0")

if [ "$(whoami)" != "root" ]; then
    perr "WARNING: the script '$shs' requires root priviledges"
    sudo bash $0 "$@"
    exit $?
fi

################################################################################

iso=${1:-}
dev=${2:-}
kmp=${3:-}

sve="changes.dat"
bgi="moonwalker-background.jpg"
bsi="moonwalker-bootscreen.png"
opt="-E lazy_itable_init=1,lazy_journal_init=1 -F"
cfg="/boot/syslinux/porteus.cfg"
mbr="porteus-usb-bootable.mbr.gz"
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

trap "echo;echo;exit 1" INT

perr "RUNNING: $shs $(basename "$iso") into /dev/$dev" ${kmp:+with $kmp}
fdisk -l /dev/${dev} >/dev/null|| exit 1
echo; fdisk -l /dev/${dev} | sed -e "s,^.*$,\t&,"
perr "WARNING: all data on '/dev/$dev' will be LOST"
sure

# Clear previous failed runs, eventually
umount ${src} ${dst} 2>/dev/null || true
umount /dev/${dev}? 2>/dev/null || true
echo
if mount | grep /dev/${dev}; then
    perr "ERROR: device /dev/${dev} is busy, abort!"
    echo
    exit 1
fi
mkdir -p ${lpd} ${dst} ${src}
declare -i tms=$(date +%s%N)

# Write MBR and basic partition table
zcat ${mbr} >/dev/${dev}; waitdev ${dev}1

# Prepare partitions and filesystems
mkfs.vfat -n Porteus /dev/${dev}1
printf "n\np\n2\n\n\nw\n" | fdisk /dev/${dev}; waitdev ${dev}2
mke4fs "Portdata" /dev/${dev}2

# Mount source and destination devices
mkdir -p ${dst} ${src}; mount /dev/${dev}1 ${dst}
mount -o loop ${iso} ${src}

# Copying Porteus files from ISO file
cp -arf ${src}/* ${dst}
sync -f ${dst}${cfg} &

# Creating persistence loop filesystem
dd if=/dev/zero count=1 seek=${blocks} of=${sve}
mke4fs "changes" ${sve} ${journal}
if test -n "${bsi}"; then
    mount -o loop ${sve} ${lpd}
    mkdir -p ${lpd}/usr/share/wallpapers/
    cp ${bgi} ${lpd}/usr/share/wallpapers/porteus.jpg
    chmod a+r ${lpd}/usr/share/wallpapers/porteus.jpg
    echo "INFO: custom background '${bgi}' copied"
    umount ${lpd}
fi

# Moving persistence and configure it
perr "INFO: waiting for fsdata synchronisation..."
wait
test -r ${dst}${cfg} || missing ${dst}${cfg}
if test -n "${bsi}" && cp -f ${bsi} ${dst}/boot/syslinux/porteus.png;
   then echo "INFO: custom boot screen background '${bsi}' copied"; fi
sed -e "s,APPEND changes=/porteus$,&/${sve} ${kmp}," -i ${dst}${cfg}
grep -n "changes=/porteus/${sve}" ${dst}${cfg}
mv -f ${sve} ${dst}/porteus/

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
