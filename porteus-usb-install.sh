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
usage_strn="[--user-menu] /path/file.iso [/dev/]sdx [it] [--ext4-install]"

export DEVEL=${DEVEL:-0}

# RAF: these values depend by external sources and [TODO] should be shared #____

# RAF: internal values #________________________________________________________

## Name of the loop file for having the persistence with a VFAT only system
persistnce_filename="changes.dat"
kernelargs_filename="cmdline.txt"

## Comment this line below to avoid creating the journal in the 2nd partition
journal="yes"

## This below is the default size in 512-blocks for the persistent loop file
blocks="256K"

## Some more options / parameters that might be worth to be customised
make_ext4_nojournal="-O ^has_journal"
make_ext4fs_options="-DO fast_commit"
make_ext4fs_lazyone="-E lazy_itable_init=1,lazy_journal_init=1"
make_ext4fs_notlazy="-E lazy_itable_init=0,lazy_journal_init=0"
porteus_config_path="/boot/syslinux/porteus.cfg"
background_filename="moonwalker-background.jpg"
bootscreen_filename="moonwalker-bootscreen.png"
usbsk_init_filename="porteus-usb-bootable.mbr.gz"

# RAF: basic common functions #_________________________________________________

function is_menu_mode() { grep -q -- "--user-menu" /proc/$$/cmdline; }
function asking_help() { grep -qe "help" -e "\-h" /proc/$$/cmdline; }
function is_on_demand() { echo "$0" | grep -q "/dev/fd/"; }
function isdevel() { test "${DEVEL:-0}" != "0"; }
function perr() { { printf "$@"; } >&2; }
function errexit() { echo; exit ${1:-1}; }

function amiroot() {
    test "$EUID" == "0" -o "$ID" == "0" -o "$(whoami)" == "root"
}

function usage() {
    printf \\n"USAGE: bash ${shs:-$(basename $0)} $usage_strn"\\n
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

if is_on_demand; then
    wdr=$PWD
    perr \\n"###############################################"
    perr \\n"This is an on-demand from remote running script"
    perr \\n"###############################################"\\n\\n
fi

workingd_path=$(dirname $(realpath "$0"))
download_path=${download_path:-$PWD}
if [ "$(basename $PWD)" != "$store_dirn" ]; then
    download_path="$download_path/$store_dirn"
fi

if isdevel; then
    perr \\n"download path: $download_path\nworkingd path: $workingd_path"\\n
elif amiroot; then
    : # RAF: if the user just did sudo or uid=0, do not drop priviledges caching
else
    # RAF: this could be annoying for DEVs but is an extra safety USR checkpoint
    sudo -k
fi

# RAF: internal check & set and early functions #_______________________________

if is_on_demand; then
    perr \\n"ERROR: this script is NOT supposed being executed on-demand, abort!"
    perr \\n"       For remote installation, use porteus-net-install.sh, instead"\\n
    errexit
fi

################################################################################
if asking_help; then usage errexit 0; else ##################################

function missing() {
    perr \\n"ERROR: file '${1:-}' is missing or wrong type, abort!"\\n
    errexit
}

function besure() {
    local ans
    echo
    read -p "${1:-Are you sure to continue}? [N/y] " ans
    ans=${ans^^}; test "${ans:0:1}" == "Y" || return 1
}

function agree() {
    local ans
    echo; read -p "${1:-Are you sure to continue}? [Y/n] " ans
    ans=${ans^^}; test "${ans:0:1}" != "N" || return 1
}

function waitdev() {
    local i
    partprobe
    for i in $(seq 1 100); do
        if grep -q " $1$" /proc/partitions; then
            test -b /dev/$1
            return $?
        fi; printf .
        sleep 0.1
    done
    perr \\n"ERROR: waitdev('$1') failed, abort!"\\n
    errexit
}

function make4fs() {
    local lbl=$1 dev=$2; shift 2
    $time mkfs.ext4 -L "$lbl" ${make_ext4fs_options} -F $dev "$@"
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
    echo
    if [ ! -b /dev/$dev ]; then
        perr "WARNING: error '${dev:+/dev/$dev}' is not a block device, abort!"\\n
        errexit
    fi
    if [ ! -n "$scsi_dev" ]; then
        perr "WARNING: to write on '/dev/$dev' but unable to find the last attached unit."\\n
        besure || errexit
    elif [ "$scsi_dev" != "$dev" ]; then
        perr "WARNING: to write on '/dev/$dev' but '/dev/$scsi_dev' is the last attached unit."\\n
        perr \\n"$scsi_str"\\n
        besure || errexit
    else
        echo "$scsi_str"
    fi
}

function check_dmsg_for_last_attached_scsi() {
    find_last_attached_scsi_unit     # producer
    check_last_attached_scsi_unit $1 # user
    scsi_str=""; scsi_dev=""         # consumer
}

function timereal() {
    ( eval "${@:-false}" || echo "real:error($@) $?" ) \
        2>&1 | time -f%e cat | grep "real:."
}

################################################################################

trap 'printf "\n\n"; exit 1' INT

declare -i extfs=0 usrmn=0

if is_menu_mode; then
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
str=$(search "$kernelargs_filename" ||:)
kargs=${str:+$(cat "$str" 2>/dev/null ||:)}

sve=$persistnce_filename
bgi=$background_filename
bsi=$bootscreen_filename
cfg=$porteus_config_path
mbr=$usbsk_init_filename

if ! is_menu_mode; then
    test -b "/dev/$dev" || dev=$(basename "$dev")
    test -b "/dev/$dev" || usage missing "${dev:+/dev/}${dev:-block_device}"
    test -r "$iso" || iso="$wdr/$iso"
    test -r "$iso" || usage missing "$iso"
fi

test -r "$bsi" || bsi="$wdr/$bsi"
test -f "$bsi" || bsi=""

test -r "$bgi" || bgi="$wdr/$bgi"
test -f "$bgi" || bgi=""

test -r "$mbr" || mbr="$wdr/$mbr"
test -r "$mbr" || usage missing "$mbr"

if ! amiroot; then
    printf \\n"WARNING: script '$shs'${dev:+for '/dev/$dev'} requires root priviledges (devel:${DEVEL:-0}) (menu:$usrmn)."\\n
    # RAF: this could be annoying for DEVs but is an extra safety USR checkpoint
    isdevel || { amiroot || sudo -k; }
    is_menu_mode && set -- "--user-menu"
    exec sudo -E bash $0 "$@" # exec replaces this process, no return from here
    perr \\n"ERROR: exec fails or a bug hits here, abort!"\\n
    errexit -1
fi

nice -19 sync & # RAF: a wait expects to join with this process in background
sync_pid=$!

str=${usrmn/1/user menu mode active}
str=${str/0/(none)}
echo "
Executing shell script from: $wdr
       current working path: $PWD
           script file name: $shs
              with oprtions: ${@:-$str}
              kern. cmdline: ${kargs:-(none)}
                    by user: ${SUDO_USER:+$SUDO_USER as }${USER} 
                      devel: ${DEVEL:-unset}"

if is_menu_mode; then
    # RAF: selecting the device by insertion is the most user-friendly way to go
    while true; do
        find_last_attached_scsi_unit
        test -b /dev/$scsi_dev && break
        echo
        read -p "Waiting for the USB stick insertion, press ENTER to continue";
        sleep 1
    done
    echo
    echo "$scsi_str"
    agree "This above is the last unit attached, select it" || usage errexit
    dev=$scsi_dev

    # RAF: auto-selection for ISO, priority: 1. folder; 2. newest
    for d in . "${store_dirn}" "$wdr"; do
        iso=$(command ls -1t "$d"/*.iso "$d"/*.ISO 2>/dev/null ||:)
        test -n "$iso" && break
    done
    # RAF, TODO: if many ISO found, let the user choose among them
    iso=$(echo "$iso" | head -n1)
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
test -n "$kmp" && kargs="kmap=$kmp ${kargs}"

# Deciding about time keeping and its format
# time=""; isdevel && time=$(which time)
#time=$(which time)
#time=${time:+$time -freal:"%es\n"}
time='time -freal:%es\n'

# Deciding about output redirection
redir="/dev/null"; isdevel && redir="/dev/stdout"

################################################################################

trap 'for i in $src $dst $dst; do umount $i 2>/dev/null||:; done &' EXIT

# ---------------------------------------------------------------------- FUNC --

function spcut() { tr -s ' ' | cut -d ' ' -f$1; }

function is_ext4_install() { test $extfs -eq 4; }

function get_diskpart_size() { 
    declare -i nb;
    if ! cat /sys/block/${dev}$1/size 2>/dev/null; then
        nb=$(sed -ne "s,.* \([0-9]\+\) *${dev}$1$,\\1,p" /proc/partitions)
        echo $[nb*2] # RAF: in /proc/partition #blocks are 1KB not 512-bytes
    fi
}

function devflush() {
    blockdev --flushbufs /dev/${dev}$1 || hdparm -f /dev/${dev} || sleep 1
}

function ddsync() {
    local alt=$1; shift; { dd "$@" oflag=dsync 2>&1 || $1; }| grep -v "records"
}

function smart_make_ext4() {
    local opts="${make_ext4_nojournal} ${make_ext4fs_lazyone}"
    # declare -i ng max=512 # RAF, TODO: 32 but differentiate 2.0 from 3.0, helps
    # let ng=($(get_diskpart_size)/2048)/1024
    # if [ $ng -ge $max -a "$journal" == "yes" ]; then
    if is_ext4_install; then
        #perr "INFO: usbstick size $ng GiB < $max Gib, init journal with mkfs."\\n
        printf "INFO: journaling INIT, will be added WHILE copying, wait..."\\n\\n
        opts="-J size=16 ${make_ext4fs_notlazy}"
    else
        printf "INFO: journaling SKIP, will be added AFTER copying, wait..."\\n\\n
    fi
    waitdev ${dev}2
    make4fs "$1" /dev/${dev}2 $opts
}

# ------------------------------------------------------------------------------
# RAF: TODO: here is better to use mktemp, instead
#
dst="/tmp/usb"
src="/tmp/iso"

printf \\n"INFO: wake-up the chosen device and rescan the partitions, wait..."\\n
eject -t /dev/${dev}  # RAF: give the device a wake-up, just in case
sleep 0.25
partprobe

echo
echo "RUNNING: $shs writes on /dev/$dev with extfs:$extfs"
echo "         ISO filepath: $iso"
echo "         kernel. opts: ${kargs:-(none)}"
echo; fdisk -l /dev/${dev} >/dev/null || errexit $?
{     fdisk -l /dev/${dev}
      echo
      smartctl -H -d scsi /dev/${dev} 2>/dev/null | grep -i health ||:
      echo
      mount | cut -d\( -f1 | grep "/dev/${dev}" | sort -n \
  | sed -e "s,^.*$,& <-- MOUNTED !!," | grep . ||:
} | sed -e "s,^.*$,\t &,"
besure "WARNING
WARNING: data on '/dev/$dev' and its partitions will be permanently LOST !!
WARNING
WARNING: Are you sure to proceed" || errexit
if ! is_menu_mode; then
    check_dmsg_for_last_attached_scsi "$dev"
fi
if [ -e /proc/$sync_pid ]; then
    perr \\n"WARNING: system busy, waiting for sync (pid:$sync_pid) returns..."\\n
    wait $sync_pid
fi

# Clear previous failed runs, eventually
umount ${src} ${dst} 2>/dev/null || true
umount /dev/${dev}* 2>/dev/null || true 
echo
if mount | grep /dev/${dev}; then
    perr \\n"ERROR: device /dev/${dev} is busy, abort!"\\n
    errexit
fi
mkdir -p ${dst} ${src}

# Keep the time from here #_____________________________________________________

declare -i tms=$(date +%s%N)

# RAF: zeroing the filesystem signatures prevents automounting #________________

printf "INFO: invalidating all previous filesystem signatures"
if which wipefs >/dev/null; then
    printf " ... "
    $time wipefs --all /dev/${dev}1 /dev/${dev}2 2>&1|grep -v "offset 0x"
else
    printf ", wait..."\\n\\n
    for i in /dev/${dev}?; do
        if [ ! -b $i ]; then test -f $i && rm -f $i; continue; fi
        ddsync : if=/dev/zero bs=4M count=1 of=$i
        #dd if=/dev/zero bs=4M count=1 of=$i oflag=dsync 2>&1|grep -v "records"
    done
    echo
fi

# Write MBR and essential partition table #_____________________________________

printf "INFO: writing the MBR and preparing essential partitions, wait... "\\n\\n
{ zcat "${mbr}" || errexit; } |\
    ddsync errexit bs=1M iflag=fullblock of=/dev/${dev}
devflush ; waitdev ${dev}1
echo
if is_ext4_install; then # --------------------------------------------- EXT4 --
    printf "d_n_p_1_ _+16M_t_7_a_n_p_2_ _+1G_w_" |\
        tr _ '\n' | fdisk /dev/${dev} >$redir
    smart_make_ext4 "porteus"
    #printf \\n"INFO: resizing the EXT4 filesystem to 1GB, wait..."\\n
    #$time resize2fs /dev/${dev}2 1G 1>&2 ||:  
else # ----------------------------------------------------------------- VFAT --
    $time mkfs.vfat -a -F32 -n "PORTEUS" /dev/${dev}1 2>&1
    printf "n_p_2_ _+1G_w_" | tr _ '\n' | fdisk /dev/${dev} >$redir
    smart_make_ext4 "usrdata"
fi #2>&1 >$redir # --------------------------------------------------------------

if is_ext4_install; then # --------------------------------------------- EXT4 --
    #set -x
    declare -i nb=$(get_diskpart_size 1)
    printf "INFO: creating a tmpfs image (szb:$nb) to init VFAT partition, wait..."\\n\\n
    mount -t tmpfs tmpfs ${dst}
    dd if=/dev/zero count=$nb of=${dst}/vfat.img status=none
    if ! $time mkfs.vfat -n EFIBOOT -aI ${dst}/vfat.img; then
        rm -f ${dst}/vfat.img; errexit
    fi
    mount -o loop ${dst}/vfat.img ${dst}
    #set +x
else # ----------------------------------------------------------------- VFAT --
    printf "INFO: mounting /dev/${dev}1 on ${dst}, wait..."\\n\\n
    devflush 1 ; waitdev ${dev}1
    mount -o async,noatime /dev/${dev}1 ${dst} || errexit
    mount | grep -qw /dev/${dev}1 || errexit
    echo
fi # ---------------------------------------------------------------------------

# Copying Porteus EFI/boot files from ISO file #________________________________

mount -o loop,ro ${iso} ${src} || errexit
printf "INFO: copying Porteus EFI/boot files from ISO file ... "
$time cp -arf ${src}/boot ${src}/EFI ${dst} 2>&1
test -r ${dst}/${cfg} || missing ${dst}/${cfg}
str=" ${kargs}"; is_ext4_install || str="/${sve} ${kargs}"
sed -e "s,APPEND changes=/porteus$,&${str}," -i ${dst}/${cfg}
grep -n  "APPEND changes=/porteus${str}" ${dst}/${cfg}
if test -n "${bsi}" && cp -f ${bsi} ${dst}/boot/syslinux/porteus.png; then
    printf \\n"INFO: custom boot screen background '${bsi}' copied"\\n
fi

# Creating persistence loop filesystem or umount #______________________________

if is_ext4_install; then # --------------------------------------------- EXT4 --
    umount ${dst}
    printf \\n"INFO: writing the VFAT loopfile to /dev/${dev}1, wait..."\\n\\n
    ddsync errexit if=${dst}/vfat.img bs=1M of=/dev/${dev}1
    devflush 1
    rm -f ${dst}/vfat.img; umount ${dst}
    mount -o async,noatime /dev/${dev}2 ${dst}
    echo
else # ----------------------------------------------------------------- VFAT --
    printf \\n"INFO: writing the EXT4 persistence file to changes, wait..."\\n\\n
    dd if=/dev/zero count=1 seek=${blocks} of=${sve} status=none
    make4fs "changes" ${sve} ${make_ext4_nojournal} ${make_ext4fs_lazyone} >$redir
    d=${dst}/porteus; mkdir -p $d
    $time cp -f ${sve} $d
    rm -f ${sve}
    # RAF: using cp instead of mv because it handles the sparse
fi # ---------------------------------------------------------------------------

# Copying Porteus system and modules from ISO file#_____________________________

printf "INFO: copying Porteus core system files ... "
$time cp -arf ${src}/*.txt ${src}/porteus ${dst} 2>&1
if [ -n "${bsi}" ]; then
    lpd=${dst}/porteus/rootcopy
    mkdir -p ${lpd}/usr/share/wallpapers/
    cp ${bgi} ${lpd}/usr/share/wallpapers/porteus.jpg
    chmod a+r ${lpd}/usr/share/wallpapers/porteus.jpg
    printf "INFO: custom background '${bgi}' copied"\\n
fi
#sync -f ${dst}/*.txt &

# Unmount source and eject USB device #_________________________________________
set +xe

function flush_umount_device() {
    local i; 
    if false && [ -e /proc/sys/kernel/sysrq ]; then
        while grep -Eq "${dev}[1-2]*$" /proc/partitions; do sleep 360
            echo s >/proc/sys/kernel/sysrq 2>/dev/null; done &
    fi
    devflush
    (
        nice -19 sync -f ${dst}/*.txt 2>/dev/null &
        devflush 1; umount /dev/${dev}1 
        devflush 2; umount /dev/${dev}2
        wait

        for i in ${dst} ${src} /dev/${dev}?; do
            while mount | grep -wq $i; do
                umount $i && break
                sleep 1
            done
        done 
    ) 2>&1 | grep -v ": not mounted."
    
    { mount | grep /dev/${dev} && echo; }| sed -e "s/.\+/ERROR: &/" >&2
}

printf \\n"INFO: minute(s) long WAITING for the unmount synchronisation ... "
timereal flush_umount_device

if false; [ "$journal" == "yes" ]; then #$ng -lt 16 -a
    printf \\n"INFO: creating the journal and then checking, wait..."\\n\\n
    $time tune2fs -O fast_commit -J size=16 /dev/${dev}2
else echo; fi

for i in 1 2; do
    for n in 1 2 3; do
        fsck -yf /dev/${dev}$i && break
        echo
    done
    echo
done; flush_umount_device

# Say goodbye and exit #________________________________________________________

mkdir -p   ${dst}1 ${dst}2
mount /dev/${dev}1 ${dst}1
mount /dev/${dev}2 ${dst}2
udsc="$(df -h | grep -e /dev/${dev} -e Filesyst)"
#udsc1=$(fdisk -l /dev/${dev} | head -n2 | cut -d' ' -f2- | cut -d, -f1 | sed -e 's,\(model:\), \1,')
#udsc2=$(for i in 1 2; do eval $(blkid -o export /dev/${dev}$i); printf "$DEVNAME $LABEL $TYPE\n"; done)
while ! eject /dev/${dev}
    do sleep 1; done
let tms=($(date +%s%N)-$tms+500000000)/1000000000
if is_ext4_install; then str="EXT4"; else str="LIVE"; fi
printf "INFO: Creation $str usbstick completed in $tms seconds."\\n\\n
#printf "      $udsc1"  | tr '\n' '\t'; echo
#printf "      $udsc2"  | tr '\n' '\t'; echo; echo
echo "$udsc"; echo
printf "DONE: Your bootable USB key ready to be removed safely."\\n\\n
for i in $(pgrep -x "sleep"); do cat /proc/$i/cmdline |\
    tr -d '\0' | grep -q sleep360 && kill $i; done 2>/dev/null
trap - EXIT
wait

fi #############################################################################

