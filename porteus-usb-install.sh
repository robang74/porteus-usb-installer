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

guest_owner="1000:100" # guest:users
make_ext4_nojournal="-O ^has_journal"
make_ext4fs_options="-DO fast_commit"
make_ext4fs_lazyone="-E lazy_itable_init=1,lazy_journal_init=1"
make_ext4fs_notlazy="-E lazy_itable_init=0,lazy_journal_init=0"

porteus=${VARIANT:-porteus}
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
    local i d=${dev}$1
    for i in $(seq 1 100); do
        sleep 0.1
        partprobe
        if grep -q " $d$" /proc/partitions; then
            test -b /dev/$d
            return $?
        fi; printf .
    done
    perr \\n"ERROR: waitdev('$d') failed, abort!"\\n
    errexit
}

function make4fs() {
    local lbl=$1 dev=$2; shift 2
    { mkfs.ext4 -L "$lbl" ${make_ext4fs_options} -F $dev "$@" || errexit; } \
        2>&1 | grep -v "^mke2fs [0-9.]\+ (" ||:
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

time='time -freal:%es\n'

function timereal() {
    local time=${time:-time -freal:%es\n}
    ( eval "${@:-false}" || echo "real:error($?)" )  \
         | $time cat 2>&1 | grep -e "real:."
}

function umount_all() {
    local ret=0 i; for i in 1 2 3; do
        umount ${src} ${dst} ${mem} /dev/${dev}* ||:
    done 2>/dev/null
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

str="/proc/sys/kernel/sysrq"
if test -e $str && echo s >$str; then
    :
else
    nice -19 sync & # RAF: a wait expects to join with this process in background
    sync_pid=$!
fi 2>/dev/null

str=${usrmn/1/user menu mode active}
str=${str/0/(none)}
echo "
Executing shell script from: $wdr
       current working path: $PWD
           script file name: $shs
              with oprtions: ${@:-$str}
              kern. cmdline: ${kargs:-(none)}
                    by user: ${SUDO_USER:+$SUDO_USER as }${USER}
                    variant: ${porteus}
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

# Deciding about output redirection
redir="/dev/null"; isdevel && redir="/dev/stdout"

################################################################################

trap 'umount_all &' EXIT

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
    local alt=$1; shift;
    { dd "$@" bs=1M oflag=dsync 2>&1 || $1; }| grep -v "records" ||:
}

function smart_make_ext4() {
    local opts="${make_ext4_nojournal} ${make_ext4fs_lazyone}"
    # declare -i ng max=512 # RAF, TODO: 32 but differentiate 2.0 from 3.0, helps
    # let ng=($(get_diskpart_size)/2048)/1024
    # if [ $ng -ge $max -a "$journal" == "yes" ]; then
    echo
    if ! is_ext4_install; then
        #perr "INFO: usbstick size $ng GiB < $max Gib, init journal with mkfs."\\n
        print_dtms "" "INFO: journaling INIT, will be added WHILE copying ... "
        opts="${make_ext4fs_notlazy} -J size=16"
        journal="no"
    else
        print_dtms "" "INFO: journaling SKIP, will be added AFTER copying ... "
    fi
    timereal make4fs "$1" $2 $opts
    echo
}

function mk_tmp_dir() {
    local d2=${dst}2 d1=${dst}1
    mkdir -p ${d1} ${d2}
    mount /dev/${dev}1 ${d1}
    mount /dev/${dev}2 ${d2}
    mkdir -p ${d2}/tmp
    chmod a+wrx ${d2}/tmp
}

function new_disk_id() {
    local diskid=$(echo $RANDOM | md5sum | head -c8)
    echo "x_i_0x${diskid}_r_w" | tr '_' '\n' | fdisk $1 >/dev/null ||:
}

function get_avail_mem() {
    echo $(free -m | sed -ne "s/Mem:.* \([0-9]\+\)/\\1/p")
    return $?
#   local ms="MemAvailable"
#   declare -i mbmem=$(sed -ne "s/$ms:.* \([0-9]\+\) kB/\\1/p" /proc/meminfo)
#   let mbmem/=1024; echo $mbmem; return 0
}

function dofdisk() { 
    { echo "${1}w" | tr _ '\n' | fdisk $2 || errexit; } >$redir 2>&1
}

# ------------------------------------------------------------------------------
# RAF: TODO: here is better to use mktemp, instead
#
dst="/tmp/usb"
src="/tmp/iso"
mem="/tmp/mem"

printf \\n"INFO: wake-up the chosen device and rescan the partitions, wait..."\\n
# RAF: give the device a wake-up, just in case
str=$(eject -t /dev/${dev} 2>&1 ||:)
if [ ! -n "$str" ]; then
    sleep 0.25
    partprobe
elif echo "$str" | grep -q "CD-ROM"; then
    CDROM=1
else
    echo "$str" >&2
    errexit
fi

echo
echo "RUNNING: $shs writes on /dev/$dev with extfs:$extfs"
echo "         ISO filepath: $iso"
echo "         kernel. opts: ${kargs:-(none)}"
echo; fdisk -l /dev/${dev} >/dev/null || errexit $?
{     fdisk -l /dev/${dev}
  if [ "$CDROM" != "1" ]; then
      echo # RAF: this check takes too long, skipping when CDROM=1
      smartctl -H -d scsi /dev/${dev} 2>/dev/null | grep -i health ||: 
  fi
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

if [ -n "$sync_pid" -a -e /proc/$sync_pid ]; then
    perr \\n"WARNING: system busy, waiting for sync (pid:$sync_pid) returns..."\\n
    sleep 0.25; sync; wait $sync_pid ||:; sync; sync
else
    perr \\n"INFO: before proceding sync the system I/O pending operations, wait..."\\n
    sleep 0.25; sync; sync; sync
fi

str=$(lsof /dev/${dev}* 2>/dev/null ||:)
test -n "$str" && printf \\n"$str"\\n

# Clear previous failed runs, eventually
umount_all
echo
if mount | grep /dev/${dev}; then
    perr \\n"ERROR: device /dev/${dev} is busy, abort!"\\n
    errexit
fi
mkdir -p ${dst} ${src} ${mem}

declare -i AVAIL_MEMORY=$(get_avail_mem) IMGSIZE=0
test ${AVAIL_MEMORY} -gt 800 && IMGSIZE=700

# Keep the time from here #_____________________________________________________

print_dtms() {
    local nl=$1; shift
    let dtms=($(date +%s%N)-$tms+5000000)/10000000 ||:
    printf "${nl}>[%3d.%02d] $@" $[dtms/100] $[dtms%100]
}
declare -i nsec dtms tms=$(date +%s%N)

function ddzero() {
    { dd if=/dev/zero oflag=nonblock "$@" 2>&1 || errexit; } |\
        grep -v "records" ||:;
}

# RAF: zeroing the filesystem signatures prevents automounting #________________

print_dtms "" "INFO: invalidating all previous filesystem signatures"
if which wipefs >/dev/null; then
    printf " ... "
    timereal "wipefs --all /dev/${dev}1 /dev/${dev}2 2>/dev/null ||:" \
        2>&1 | grep -v 'offset 0x' ||:
    print_dtms "" "INFO: invalidating all previous partitions"
fi
printf ", wait..."\\n\\n
for i in /dev/${dev}1 /dev/${dev}2; do
    if [ ! -b $i ]; then rm -f $i; continue; fi
    printf "$i: "; ddzero bs=1M count=4 of=$i
done |{ grep --color=never . || echo "nothing to do."; } | tabout
i=/dev/${dev}; if [ -b $i ]; then
    ddzero of=$i count=1 status=none; fi

# Write MBR and essential partition table #_____________________________________

print_dtms \\n "INFO: writing the MBR and preparing essential partitions, wait... "\\n\\n
#set -x
mount -t tmpfs tmpfs ${dst} 
printf "/dev/${dev}: " | tabout
f=${dst}/mbr.img; zcat "${mbr}" >$f; new_disk_id $f
ddsync errexit iflag=fullblock if=$f of=/dev/${dev}
for i in "" 1 2; do devflush $i ||:; done >/dev/null 2>&1
waitdev 1; rm -f $f

# Write EXT4 partition #________________________________________________________

if is_ext4_install; then # --------------------------------------------- EXT4 --
    dofdisk "d_n_p_1_ _+16M_y_t_7_a_n_p_2_ _+1880M_" /dev/${dev}
    devflush; waitdev 2
    smart_make_ext4 "${porteus}" /dev/${dev}2
    usb_type="EXT4/INST"
else # ----------------------------------------------------------------- VFAT --
    dofdisk "d_n_p_1_ _+1200M_y_t_7_a_n_p_2_ _+700M_" /dev/${dev}
    devflush; waitdev 2
    smart_make_ext4 "usrdata" /dev/${dev}2
    usb_type="VFAT/LIVE"
fi #----------------------------------------------------------------------------

waitdev 2; umount /dev/${dev}? 2>/dev/null ||:

#exit

# Write VFAT partition #________________________________________________________

if is_ext4_install; then # --------------------------------------------- EXT4 --
    declare -i nb=$(get_diskpart_size 1)
    print_dtms "" "INFO: creating a tmpfs image (szb:$nb) to init VFAT partition ... "
    ddzero count=$nb of=${dst}/vfat.img status=none
    if ! timereal mkfs.vfat -n EFIBOOT -aI ${dst}/vfat.img; then
        rm -f ${dst}/vfat.img; umount ${dst}; errexit
    fi
    mount -o loop ${dst}/vfat.img ${dst}
else # ----------------------------------------------------------------- VFAT --
    str="${porteus}"
    print_dtms "" "INFO: writing creating VFAT $str filesystem ... "
    timereal mkfs.vfat -a -F32 -n "${str^^}" /dev/${dev}1
    print_dtms "" "INFO: mounting /dev/${dev}1 on ${dst}, wait..."\\n
    devflush 1 ; waitdev 1
    mount -o async,noatime /dev/${dev}1 ${dst}
    mount | grep -qw /dev/${dev}1 || errexit

fi # ---------------------------------------------------------------------------

# Copying Porteus EFI/boot files from ISO file #________________________________

function cpvfatext4 {
    _cpvfatext4() {
        ({ cp  -arf "$@" || errexit; } 2>&1 |\
            grep -v "failed to preserve ownership" ||:)
    }
    timereal _cpvfatext4 "$@"
}

mount -o loop,ro ${iso} ${src} || errexit
print_dtms \\n "INFO: copying ${porteus^} EFI/boot files from ISO file ... "
cpvfatext4 ${src}/boot ${src}/EFI ${dst}

# RAF: these executables might not work w/moonwalker edition
rm -f ${dst}/boot/*.{com,exe,run} 2>/dev/null ||:

function porteus_configure() {
    local str i b p f d
    f="${dst}/${porteus}/${porteus}.cfg"
    p="${dst}/boot/syslinux/bootlogo.png"
    b="${dst}/boot/syslinux/${porteus}.png"
    if [ -r ${bsi} ]; then
        if [ -r $p ]; then
            cp -f ${bsi} $p && d="bootlog.png"
        else
            cp -f ${bsi} $b && d="${porteus}.png"
        fi 2>/dev/null
        test -n "$d" &&\
            print_dtms \\n "INFO: custom boot screen background '$d' copied"\\n
    fi
    if [ -r $f ]; then
        str="chages=/${porteus}"
        is_ext4_install || str="${str}/${sve}"
        for i in ${str} ${kargs}; do echo "$i" >>$f; done
        cat $f | cut -d\# -f1 | grep . | tr '\n' ' ' |\
            { grep . && echo; } | tabout
    elif [ -r ${dst}/${cfg} ]; then
        str=" ${kargs}"; is_ext4_install || str="/${sve} ${kargs}"
        sed -e "s,APPEND changes=/${porteus}$,&${str}," -i ${dst}/${cfg}
        echo; grep -n "APPEND changes=/${porteus}${str}" ${dst}/${cfg}  | tabout
    else
        return 1
    fi
    return 0
}

yet2cfg="yes"; porteus_configure && yet2cfg="no"

# Creating persistence loop filesystem or umount #______________________________

function create_and_copy_changes_loopfile() {
    local d opts="${make_ext4_nojournal} ${make_ext4fs_lazyone}"
    ddzero count=1 seek=${blocks} of=${sve} status=none
    make4fs 'changes' ${sve} $opts
    d=${dst}/${porteus}; mkdir -p $d
    cp -f ${sve} $d; rm -f ${sve}
}

if is_ext4_install; then # --------------------------------------------- EXT4 --
    umount ${dst}
    print_dtms \\n "INFO: writing the VFAT loopfile to usbstick, wait..."\\n\\n
    printf "/dev/${dev}1: " | tabout
    ddsync errexit if=${dst}/vfat.img of=/dev/${dev}1
    devflush 1; rm -f ${dst}/vfat.img; umount ${dst}
    mount -o async,noatime /dev/${dev}2 ${dst}
else # ----------------------------------------------------------------- VFAT --
    print_dtms \\n "INFO: writing the EXT4 persistence file to changes ... "
    timereal "create_and_copy_changes_loopfile"
    # RAF: using cp instead of mv because it handles the sparse
if false; then
    d=${dst}/${porteus}; mkdir -p $d
    str="cp -f ${sve} $d"; printf "$str ... "
    timereal "$str"; rm -f ${sve}
fi
fi # ---------------------------------------------------------------------------

# Copying Porteus system and modules from ISO file#_____________________________

print_dtms \\n "INFO: copying ${porteus^} core system files ... "
cpvfatext4 ${src}/*.txt ${src}/${porteus} ${dst}; echo
du -m ${dst}/${porteus}/*/*.xzm 2>&1 | sort -n | tabout

function is_real_porteus() { test "${porteus}" == "porteus"; }

if is_real_porteus; then
    d=$(dirname $iso); lst=$(ls -1 $d/*.xzm 2>/dev/null ||:)
    if [ -n "$lst" ]; then
        print_dtms \\n "INFO: copying ${porteus^} modules files ... "
        if false; then
            d=${dst}/${porteus}/modules; cpvfatext4 $lst $d/
        else
            d=${dst}/${porteus}/base; cpvfatext4 $lst $d/
            for f in $(echo "$lst" | grep -e "transition-" ||:); do
                f=$(basename $f); mv $d/$f $d/000-a-$f; done
            for f in $(echo "$lst" | grep -v "transition-" ||:); do
                f=$(basename $f); mv $d/$f $d/000-z-$f; done
        fi
        du -m $lst $d/*.xzm | grep . | sort -n | tabout
    fi
fi

s=$(search rootcopy ||:); if [ -n "$s" ]; then
    print_dtms \\n "INFO: copying rootcopy custom files ... "
    d=${dst}/${porteus}; cpvfatext4 $s $d/
    g=$d/rootcopy/home/guest
    s=$g/.config/dconf/${porteus}
    test -r $s.gz && zcat $s.gz > $s
    chown -R ${guest_owner} $g/ 2>/dev/null ||:
fi

echo; test "$yet2cfg" == "yes" && porteus_configure

# Unmount source and eject USB device #_________________________________________
set +e

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
        umount_all ||:; wait

        for i in ${dst} ${src} /dev/${dev}?; do
            while mount | grep -wq $i; do
                umount $i && break
                sleep 1
            done
        done 
    ) 2>&1 | grep -v ": not mounted."
    
    { mount | grep /dev/${dev} && echo; }| sed -e "s/.\+/ERROR: &/" >&2
}

function enfore_allfs_checks() {
    local i n op=$1
    for i in 1 2; do
        for n in 1 2 3; do
            fsck -y$op /dev/${dev}$i && break
            echo
        done
        echo
        op=f
    done 2>&1 | tabout
}

print_dtms "" "INFO: minute(s) long WAITING for the unmount synchronisation ... "
timereal flush_umount_device

function make_tune2fs_journal() { {
    local d=/dev/${dev}2
    { fsck -yf $d || fsck -y $d || fsck -y $d ||:; } \
        2>&1 | grep -v "^e2fsck [0-9.]\+ ("   ||:
    tune2fs -U random -O fast_commit -J size=16 $d
} 2>&1 | tabout; }

if [ "$journal" == "yes" ]; then
    print_dtms \\n "INFO: creating the journal and then checking ... "
    timereal make_tune2fs_journal
fi

if false; then
    print_dtms \\n "INFO: resizing EXT4 data partition to fit the whole disk ... "
    echo 'd_2_n_p_2_ _ _n_w' | tr '_' '\n' | fdisk /dev/${dev} >$redir 2>&1
    d=/dev/${dev}2; timereal "waitdev 2; fsck -yf $d; resize2fs $d" 2>/dev/null
fi

print_dtms \\n "INFO: enforcing filesystems consistency checks, wait..."\\n\\n
enfore_allfs_checks

# Say goodbye and exit #________________________________________________________

mk_tmp_dir
udsc="$(df -h | grep -e /dev/${dev} -e Filesyst | tabout)"
flush_umount_device

let nsec=($(date +%s%N)-$tms+500000000)/1000000000
print_dtms "" "INFO: Creation $usb_type usbstick completed in $nsec seconds."\\n\\n
echo "$udsc"

if [ "$DEVEL_ZEROING" == "1" ]; then
    perr \\n
    perr "WARNING"\\n
    perr "WARNING: devel zeroing ... "
    timereal "
        ddsync : if=/dev/zero count=4 of=/dev/${dev}2 oflag=nonblock
        ddsync : if=/dev/zero count=4 of=/dev/${dev}1 oflag=nonblock
        ddsync : if=/dev/zero count=1 of=/dev/${dev}  oflag=nonblock
    "
    perr "WARNING"\\n
    devflush; partprobe
fi

printf \\n"device ejecting, wait... "\\n\\n | tabout
while ! eject /dev/${dev} 2>/dev/null; do sleep 1; printf .; done
print_dtms "" "DONE: Your bootable USB key ready to be removed safely."\\n\\n
for i in $(pgrep -x "sleep"); do cat /proc/$i/cmdline |\
    tr -d '\0' | grep -q sleep360 && kill $i; done 2>/dev/null
trap - EXIT
wait

fi #############################################################################

