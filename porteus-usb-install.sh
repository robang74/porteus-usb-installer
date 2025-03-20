#!/bin/bash
#
# (C) 2025, Roberto A. Foglietta <roberto.foglietta@gmail.com> - 3-clause BSD
#
################################################################################
set -e

function perr() {
    { echo; echo "$@"; } >&2
}

function usage() {
    perr "USAGE: bash $shs /path/file.iso [/dev/]sdx [it]"
    exit 1
}

function missing() {
    perr "ERROR: file '${1:-}' is missing, abort!"
    exit 1
}

function sure() {
    local ans
    echo
    read -p "Are you sure to contine [N/y] " ans
    test "$ans" == "Y" -o "$ans" == "y" && return 0
    echo
    exit 1 
}

function waitdev() {
    partprobe
    for i in $(seq 1 100); do
        egrep " $1$" /proc/partitions && return 0
        sleep 0.1
    done
    perr "ERROR: waitdev('$1') failed, abort!"
    exit 1
}

function mke4fs() {
    mkfs.ext4 -L $1 -E lazy_itable_init=1,lazy_journal_init=1 -F $2
}

wdr=$(dirname $0)
shs=$(basename $0)

if [ "$(whoami)" != "root" ]; then
    perr "WARNING: the script '$shs' requires root priviledges"
    sudo bash $0 "$@"
    exit $?
fi

iso=${1:-}
dev=${2:-}
kmp=${3:-}

sve="changes.dat"
opt="-E lazy_itable_init=1,lazy_journal_init=1 -F"
cfg="/boot/syslinux/porteus.cfg"
mbr="porteus-usb-bootable.mbr.gz"
dst="/tmp/d"
src="/tmp/s"

test -b "/dev/$dev" || dev=$(basename $dev)
test -b "/dev/$dev" || usage
test -r "$iso" || iso="$wdr/$iso"
test -r "$iso" || usage

test -r "$mbr" || mbr="$wdr/$mbr"
test -r "$mbr" || missing "$mbr"
test -n "$kmp" && kmp="kmap=$kmp"

perr "RUNNING: $shs $(basename $iso) into /dev/$dev" ${kmp:+with $kmp}
perr "WARNING: All data on '/dev/$dev' will be lost"
sure

# Clear previous failed runs, eventually
umount ${src} ${dst} 2>/dev/null || true
umount /dev/${dev}? 2>/dev/null || true
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
dd if=/dev/zero count=1 seek=1M of=${sve}
mke4fs "changes" ${sve}

# Moving persistence and configure it
wait
test -r ${dst}${cfg} || missing ${dst}${cfg}
sed -e "s,APPEND changes=/porteus$,&/${sve} ${kmp}," -i ${dst}${cfg}
grep -n "changes=/porteus/${sve}" ${dst}${cfg}
mv -f ${sve} ${dst}/porteus/

# Umount source and eject USB device
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
