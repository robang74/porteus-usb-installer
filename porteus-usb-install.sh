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
usage_strn="/path/file.iso [/dev/]sdx [it] [--ext4-install]"

export workingd_path=$(dirname $(realpath "$0"))
export download_path=${download_path:-$PWD/$store_dirn}
export mirror_file=${mirror_file:-porteus-mirror-selected.txt}
export mirror_dflt=${mirror_dflt:-https://mirrors.dotsrc.org}
export sha256_file=${sha256_file:-sha256sums.txt}

# Comment this line below to have the journal within the persistence loop file
nojournal="-O ^has_journal"

# This below is the default size in 512-blocks for the persistent loop file
blocks="256K"

################################################################################

function isondemand() { echo "$0" | grep -q "/dev/fd/"; }
function isdevel() { test "$DEVEL" == "${1:-1}"; }
function perr() { { echo; echo "$@"; } >&2; }
function errexit() { echo; exit ${1:-1}; }

function amiroot() {
    test "$EUID" == "0" -o "$ID" == "0" -o "$(whoami)" == "root"
}

function usage() {
    perr "USAGE: bash ${shs:-$(basename $0)} $usage_strn"
    eval "$@"
}

function missing() {
    perr "ERROR: file '${1:-}' is missing or wrong type, abort!"
    errexit
}

function besure() {
    local ans
    echo; read -p "${1:-Are you sure to continue}? [N/y] " ans
    ans=${ans^^}; test "${ans:0:1}" == "Y" || return 1
}

function agree() {
    local ans
    echo; read -p "${1:-Are you sure to continue}? [Y/n] " ans
    ans=${ans^^}; test "${ans:0:1}" != "N" || return 1
}

function wait_umount() {
    for i in $(seq 1 100); do
        mount | grep -q "^/dev/$dev" || return 0
        umount /dev/$dev* 2>/dev/null ||:
        sleep 0.1
        printf .
    done
    perr "WARNING: wait_umount('$dev') timeout"
    return 1
}

function waitdev() {
    local i
    partprobe; for i in $(seq 1 100); do
        if grep -q " $1$" /proc/partitions; then
            umount /dev/$dev* 2>/dev/null ||:
            return 0
        fi
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

scsi_str=""; scsi_dev="";
function find_last_attached_scsi_unit() {
    local str lst
    str=$(dmesg | grep "] sd .* removable disk" | tail -n1)
    lst=$(echo "$str" | sed -ne "s,.*\[\(sd.\)\].*,\\1,p")
    if [ ! -n "$lst" ]; then
        str=$(dmesg | grep "\[sd[a-z]\] .* removable disk" | tail -n1)
        lst=$(echo "$str" | sed -ne "s,.*\[\(sd.\)\].*,\\1,p")
    fi
    scsi_str="$str"
    scsi_dev="$lst"
}

function check_last_attached_scsi_unit() {
    local dev=$1
    if [ ! -b /dev/$dev ]; then
        perr "WARNING: error '${dev:+/dev/$dev}' is not a block device, abort!"
        errexit
    fi
    if [ ! -n "$scsi_dev" ]; then
        perr "WARNING: to write on '/dev/$dev' but unable to find the last attached unit"
        besure || errexit
    elif [ "$scsi_dev" != "$dev" ]; then
        perr "WARNING: to write on '/dev/$dev' but '/dev/$scsi_dev' is the last attached unit"
        perr "$scsi_str"
        besure || errexit
    else
        perr "$scsi_str"
    fi
}

function check_dmsg_for_last_attached_scsi() {
    find_last_attached_scsi_unit     # producer
    check_last_attached_scsi_unit $1 # user
    scsi_str=""; scsi_dev=""         # consumer
}

if [ "x$1" == "x-h" -o "x$1" == "x--help" ]; then ##############################
    usage echo
else ###########################################################################

if isondemand; then
    perr "ERROR: this script is NOT supposed being executed on-demand, abort!"
    errexit
fi

trap "echo; echo; exit 1" INT

declare -i extfs=0 usrmn=0

if [ "x$1" == "x--user-menu" ]; then
    usrmn=1; set --
else
    iso=${1:-}
fi
dev=${2:-}
if [ "x$3" == "x--ext4-install" ]; then
    extfs=4
    shift
fi
kmp=${3:-}
extfs=${4:+4}

sve="changes.dat"
bgi="moonwalker-background.jpg"
bsi="moonwalker-bootscreen.png"
opt="-E lazy_itable_init=1,lazy_journal_init=1 -F"
cfg="/boot/syslinux/porteus.cfg"
mbr="porteus-usb-bootable.mbr.gz"

# RAF, TODO: here is better to use mktemp, instead
#
dst="/tmp/usb"
src="/tmp/iso"

if [ "$usrmn" == "0" ]; then
    test -b "/dev/$dev" || dev=$(basename "$dev")
    test -b "/dev/$dev" || missing "/dev/$dev"
    test -r "$iso" || iso="$wdr/$iso"
    test -r "$iso" || missing "$iso"
fi

test -r "$bsi" || bsi="$wdr/$bsi"
test -f "$bsi" || bsi=""

test -r "$bgi" || bgi="$wdr/$bgi"
test -f "$bgi" || bgi=""

test -r "$mbr" || mbr="$wdr/$mbr"
test -r "$mbr" || missing "$mbr"

if ! amiroot; then
    perr "WARNING: script '$shs'${dev:+for '/dev/$dev'} requires root priviledges"
    echo
    # RAF: this could be annoying for DEVs but is an extra safety USR checkpoint
    test "$DEVEL" == "0" && sudo -k
    test "$usrmn" != "0" && set -- "--user-menu"
    exec sudo bash $0 "$@" # exec replaces this process, no return from here
    perr "ERROR: exec fails or a bug hits here, abort!"
    errexit -1
fi

echo "
Executing shell script from: $wdr
       current working path: $PWD
           script file name: $shs
              with oprtions: ${@:-(none)}
                    by user: ${SUDO_USER:+$SUDO_USER as }$USER"

if [ "$usrmn" != "0" ]; then
    # RAF: selecting the device by insertion is the most user-friendly way to go
    while true; do
        find_last_attached_scsi_unit
        test -b /dev/$scsi_dev && break
        perr "Waiting for the USB stick insertion, press ENTER to continue"
        read; sleep 1
    done
    perr "$scsi_str"
    agree "This above is the last unit attached, select it" || usage errexit
    dev=$scsi_dev

    # RAF: auto-selection for ISO, priority: 1. folder; 2. newest
    for d in . "${store_dirn}" "$wdr"; do
        iso=$(command ls -1t "$d"/*.iso "$d"/*.ISO 2>/dev/null ||:)
        test -n "$iso" && break
    done
    test -r "$iso" || missing "ISO:${iso:- not found}"
    agree "Is this '$iso' the ISO file you want use" || usage errexit

    while true; do
        if agree "Do you want an EXT4 installation"; then
            extfs=4; break
        elif agree "Do you want a LIVE for sporadic use" ; then
            extfs=0; break
        fi
    done

    echo; read -p \
"Please provide the 2-letter keyboard language,
or press ENTER for leave the current settings: " kmp
fi

test -n "$kmp" && kmp="kmap=$kmp"

################################################################################

perr "RUNNING: $shs $(basename "$iso") into /dev/$dev" ${kmp:+with $kmp} extfs:$extfs
fdisk -l /dev/${dev} >/dev/null || errexit $? && {
    echo; fdisk -l /dev/${dev}; echo
    mount | cut -d\( -f1 | grep "/dev/${dev}" | sed -e "s,^.*$,& <-- MOUNTED !!,"
} | sed -e "s,^.*$,\t&,"
perr "WARNING: data on '/dev/$dev' and its partitions will be permanently LOST !!"
besure || errexit
if [ "$usrmn" == "0" ]; then
    check_dmsg_for_last_attached_scsi "$dev"
fi

# Clear previous failed runs, eventually
umount ${src} ${dst} 2>/dev/null || true
umount /dev/${dev}* 2>/dev/null || true
if true; then
    for i in /dev/${dev}?; do
        if [ ! -b $i ]; then rm -f $i; continue; fi
        dd if=/dev/zero bs=1M count=1 of=$i status=none
    done
fi
echo
if mount | grep /dev/${dev}; then
    perr "ERROR: device /dev/${dev} is busy, abort!"
    errexit
fi
mkdir -p ${dst} ${src}
declare -i tms=$(date +%s%N)

# Write MBR and basic partition table
zcat ${mbr} >/dev/${dev}
waitdev ${dev}1

str=/dev/stdout
test "$DEVEL" == "0" && str="/dev/null"
# Prepare partitions and filesystems
if [ $extfs -eq 4 ]; then
    printf "d_n____+16M_t_17_a_n_____w_" |\
        tr _ '\n' | fdisk /dev/${dev}
    waitdev ${dev}2
    mkfs.vfat -n EFIBOOT /dev/${dev}1
    mke4fs "Porteus" /dev/${dev}2 #$nojournal
else
    mkfs.vfat -n Porteus /dev/${dev}1
    printf "n_p_2___w_" | tr _ '\n' |\
        fdisk /dev/${dev}
    waitdev ${dev}2
    mke4fs "Portdata" /dev/${dev}2
fi >$str

# Mount source and destination devices
echo
mkdir -p ${dst} ${src};
mount /dev/${dev}2 ${dst}
mount -o loop ${iso} ${src}

# Copying Porteus system and modules from ISO file
perr "INFO: copying porteus files..."
cp -arf ${src}/*.txt ${src}/porteus ${dst}
if test -n "${bsi}"; then
    lpd=${dst}/porteus/rootcopy
    mkdir -p ${lpd}/usr/share/wallpapers/
    cp ${bgi} ${lpd}/usr/share/wallpapers/porteus.jpg
    chmod a+r ${lpd}/usr/share/wallpapers/porteus.jpg
    perr "INFO: custom background '${bgi}' copied"
fi

perr "INFO: starting the EXT4 umount synchronisation..."
umount -r ${dst} &
dst=${dst}.vfat
mkdir -p ${dst}
mount /dev/${dev}1 ${dst}

# Copying Porteus EFI/boot files from ISO file
if true; then
    perr "INFO: copying EFI/boot files..."
    cp -arf ${src}/boot ${src}/EFI ${dst}
    test -r ${dst}/${cfg} || missing ${dst}/${cfg}
    echo
    str=" ${kmp}"; test $extfs -eq 4 || str="/${sve} ${kmp}"
    sed -e "s,APPEND changes=/porteus$,&${str}," -i ${dst}/${cfg}
    grep -n  "APPEND changes=/porteus${str}" ${dst}/${cfg}
    if test -n "${bsi}" && cp -f ${bsi} ${dst}/boot/syslinux/porteus.png; then
        perr "INFO: custom boot screen background '${bsi}' copied"
    fi
fi
time=""; which time >/dev/null && time="time -p"

if false; then
    # Creating persistence loop filesystem or umount
    if [ $extfs -eq 4 ]; then
        perr "INFO: waiting for VFAT umount synchronisation..."
        $time umount ${dst}
        #umount ${dst} &
        #dst=${dst}.p2
        mkdir -p ${dst}
        mount /dev/${dev}2 ${dst}
    else
        dd if=/dev/zero count=1 seek=${blocks} of=${sve}
        mke4fs "changes" ${sve} ${nojournal}
        mkdir -p ${dst}/porteus/
        cp -f ${sve} ${dst}/porteus/
        rm -f ${sve}
    fi
fi

set +xe
# Umount source and eject USB device
perr "INFO: waiting for LAST umount synchronisation..."
$time umount ${src} ${dst}
fg; wait_umount ${dev}
echo; fsck -yf /dev/${dev}1
echo; fsck -yf /dev/${dev}2
while ! eject /dev/${dev};
    do sleep 1; done

# Say goodbye and exit

echo
let tms=($(date +%s%N)-$tms+500000000)/1000000000
echo "INFO: Installation completed in $tms seconds"
echo
echo "DONE: bootable USB key ready to be removed safely"
echo

fi #############################################################################

