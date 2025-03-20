#!/bin/bash
#
# (C) 2025, Roberto A. Foglietta <roberto.foglietta@gmail.com> - 3-clause BSD
#
################################################################################
#
# TODO: script needs to be developed further to accept parameters
#
# USAGE: bash script.sh /path/file.iso /dev/sdx [it]
#

set -ex

umount /dev/sdb? 2>/dev/null || true
zcat porteus-usb-bootable.mbr.gz >/dev/sdb; partprobe
while ! egrep " sdb1$" /proc/partitions; do sleep 0.1; done
mkfs.vfat -n Porteus /dev/sdb1
printf "n\np\n2\n\n\nw\n" | fdisk /dev/sdb; partprobe
while ! egrep " sdb2$" /proc/partitions; do sleep 0.1; done
mkfs.ext4 -L Portdata -E lazy_itable_init=1,lazy_journal_init=1 -F /dev/sdb2
mkdir -p /tmp/d /tmp/s; mount /dev/sdb1 /tmp/d
mount -o loop Porteus-MATE-v5.01-x86_64.iso /tmp/s
cp -arf /tmp/s/* /tmp/d
sync -f /tmp/d/boot/syslinux/porteus.cfg &

dd if=/dev/zero count=1 seek=1M of=changes.dat
mkfs.ext4 -L changes -E lazy_itable_init=1,lazy_journal_init=1 -F changes.dat
sed -e "s,APPEND changes=/porteus$,&/changes.dat kmap=it," -i /tmp/d/boot/syslinux/porteus.cfg
grep -n changes.dat /tmp/d/boot/syslinux/porteus.cfg

wait
mv -f changes.dat /tmp/d/porteus/
umount /tmp/s /tmp/d
eject /dev/sdb
echo
echo "USB bootable ready to safely remove"
