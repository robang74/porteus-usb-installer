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

export DEVEL=${DEVEL:-0}

# RAF: these values depend by external sources and [TODO] should be shared #____

# RAF: internal values #________________________________________________________

## Name of the loop file for having the persistence with a VFAT only system
persistnce_filename="changes.dat"

## Comment this line below to have the journal within the persistence loop file
nojournal="-O ^has_journal"

## This below is the default size in 512-blocks for the persistent loop file
blocks="256K"

## Some more options / parameters that might be worth to be customised
make_ext4fs_options="-E lazy_itable_init=1,lazy_journal_init=1 -F"
porteus_config_path="/boot/syslinux/porteus.cfg"
background_filename="moonwalker-background.jpg"
bootscreen_filename="moonwalker-bootscreen.png"
usbsk_init_filename="porteus-usb-bootable.mbr.gz"

# RAF: basic common functions #_________________________________________________

function askinghelp() { test "x$1" == "x-h" -o "x$1" == "x--help"; } 
function isondemand() { echo "$0" | grep -q "/dev/fd/"; }
function isdevel() { test "${DEVEL:-0}" != "0"; }
function perr() { { echo; echo -e "$@"; } >&2; }
function errexit() { echo; exit ${1:-1}; }

function amiroot() {
    test "$EUID" == "0" -o "$ID" == "0" -o "$(whoami)" == "root"
}

function usage() {
    perr "USAGE: bash ${shs:-$(basename $0)} $usage_strn"
    eval "$@"
}

function search() {
    local d ldirs=". $wdr" f="${1:-}"
    test -n "$f" || return 1
    test "$(basename $wdr)"  == "tmp" && ldirs="$ldirs .."
    for d in $ldirs; do
        if [ -d "$d" -a -r $d/$f ]; then echo "$d/$f"; return 0; fi
    done; return 1
}

# RAF: basic common check & set #_______________________________________________

if isondemand; then
    wdr=$PWD
    perr "###############################################"
    perr "This is an on-demand from remote running script"
    perr "###############################################"
fi

workingd_path=$(dirname $(realpath "$0"))
download_path=${download_path:-$PWD}
if [ "$(basename $PWD)" != "$store_dirn" ]; then
    download_path="$download_path/$store_dirn"
fi

if isdevel; then
    perr "download path: $download_path\nworkingd path: $workingd_path"
else
    # RAF: this could be annoying for DEVs but is an extra safety USR checkpoint
    sudo -k
fi

# RAF: internal check & set and early functions #_______________________________

if isondemand; then
    perr "ERROR: this script is NOT supposed being executed on-demand, abort!"
    perr "       For remote installation, use porteus-net-install.sh, instead"
    errexit
fi

################################################################################
if askinghelp; then usage errexit 0; else ######################################

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

function waitdev() {
    local i
    partprobe; for i in $(seq 1 100); do
        if grep -q " $1$" /proc/partitions; then
            # RAF: zeroing the filesystem signatures prevents automounting
            #sleep 1
            #umount /dev/$dev* 2>/dev/null ||:
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

################################################################################

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

sve=$persistnce_filename
bgi=$background_filename
bsi=$bootscreen_filename
opt=$make_ext4fs_options
cfg=$porteus_config_path
mbr=$usbsk_init_filename

# RAF: TODO: here is better to use mktemp, instead
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
    perr "WARNING: script '$shs'${dev:+for '/dev/$dev'} requires root priviledges (devel:${DEVEL:-0})"
    echo
    # RAF: this could be annoying for DEVs but is an extra safety USR checkpoint
    isdevel || sudo -k
    test "$usrmn" != "0" && set -- "--user-menu"
    exec sudo -E bash $0 "$@" # exec replaces this process, no return from here
    perr "ERROR: exec fails or a bug hits here, abort!"
    errexit -1
fi

echo "
Executing shell script from: $wdr
       current working path: $PWD
           script file name: $shs
              with oprtions: ${@:-(none)}
                    by user: ${SUDO_USER:+$SUDO_USER as }$USER
                      devel: ${DEVEL:-unset}"

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

# Deciding about keyboard layout
test -n "$kmp" && kmp="kmap=$kmp"

# Deciding about time keeping and its format
time=""; isdevel && time=$(which time)
time=${time:+$time -freal:%es}

# Deciding about output redirection
redir="/dev/null"; isdevel && redir="/dev/stdout"

################################################################################

perr "RUNNING: $shs $(basename "$iso") into /dev/$dev" ${kmp:+with $kmp} extfs:$extfs
echo; fdisk -l /dev/${dev} >/dev/null || errexit $? && {
    fdisk -l /dev/${dev}; echo
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
echo
if mount | grep /dev/${dev}; then
    perr "ERROR: device /dev/${dev} is busy, abort!"
    errexit
fi
mkdir -p ${dst} ${src}

# Keep the time from here
declare -i tms=$(date +%s%N)

# RAF: zeroing the filesystem signatures prevents automounting
for i in /dev/${dev}?; do
    if [ ! -b $i ]; then test -f $i && rm -f $i; continue; fi
    dd if=/dev/zero bs=32k count=1 of=$i oflag=dsync status=none
done

# Write MBR and basic partition table
zcat ${mbr} | dd bs=1M of=/dev/${dev} oflag=dsync status=none
waitdev ${dev}1

# exit 0
# Prepare partitions and filesystems
if [ $extfs -eq 4 ]; then
    printf "d_n_p_1_ _+16M_t_17_a_n_p_2_ _ _w_" |\
        tr _ '\n' | fdisk /dev/${dev}
    waitdev ${dev}2
    mkfs.vfat -n EFIBOOT /dev/${dev}1
    mke4fs "Porteus" /dev/${dev}2 #$nojournal
else
    mkfs.vfat -n Porteus /dev/${dev}1
    printf "n_p_2_ _ _w_" | tr _ '\n' |\
        fdisk /dev/${dev}
    waitdev ${dev}2
    mke4fs "Portdata" /dev/${dev}2
fi >$redir

# Mount source and destination devices
echo
mkdir -p ${dst} ${src};
mount -o async,noatime /dev/${dev}1 ${dst}
mount -o loop ${iso} ${src}

# Copying Porteus EFI/boot files from ISO file
if true; then
    perr "INFO: copying Porteus EFI/boot files from ISO file..."
    $time cp -arf ${src}/boot ${src}/EFI ${dst}
    test -r ${dst}/${cfg} || missing ${dst}/${cfg}
    echo
    str=" ${kmp}"; test $extfs -eq 4 || str="/${sve} ${kmp}"
    sed -e "s,APPEND changes=/porteus$,&${str}," -i ${dst}/${cfg}
    grep -n  "APPEND changes=/porteus${str}" ${dst}/${cfg}
    if test -n "${bsi}" && cp -f ${bsi} ${dst}/boot/syslinux/porteus.png; then
        perr "INFO: custom boot screen background '${bsi}' copied"
    fi
fi

# Creating persistence loop filesystem or umount
if [ $extfs -eq 4 ]; then
    perr "INFO: waiting for VFAT umount synchronisation..."
    $time umount ${dst} 2>&1 | tr '\n' ' '
    mount -o async,noatime /dev/${dev}2 ${dst}
else
    dd if=/dev/zero count=1 seek=${blocks} of=${sve} status=none
    mke4fs "changes" ${sve} ${nojournal} >$redir
    d=${dst}/porteus; mkdir -p $d
    cp -f ${sve} $d; rm -f ${sve}
    # RAF: using cp instead of mv because it handles the sparse
fi

# Copying Porteus system and modules from ISO file
perr "INFO: copying Porteus core system files..."
$time cp -arf ${src}/*.txt ${src}/porteus ${dst} 2>&1 | tr '\n' ' '
if test -n "${bsi}"; then
    lpd=${dst}/porteus/rootcopy
    mkdir -p ${lpd}/usr/share/wallpapers/
    cp ${bgi} ${lpd}/usr/share/wallpapers/porteus.jpg
    chmod a+r ${lpd}/usr/share/wallpapers/porteus.jpg
    perr "INFO: custom background '${bgi}' copied"
fi

set +xe
# Umount source and eject USB device
perr "INFO: waiting for LAST umount synchronisation..."
$time umount ${src} ${dst} 2>&1 | tr '\n' ' '
umount /dev/${dev}* 2>/dev/null
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

