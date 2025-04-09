#!/bin/bash
#
# (C) 2025, Roberto A. Foglietta <roberto.foglietta@gmail.com> - 3-clause BSD
#
################################################################################
set +o noclobber
set +u
set -e

lsblk -o VENDOR,MODEL,REV,TYPE,SIZE,NAME,SCHED /dev/${dev} | head -n2

size=$(half of free space)
nthr=$(nproc)
if [ $nthr -le 1 ]; then nthr=""; 
elif [ $nthr -le 4 ]; then ncpu=$[ncpu/2];

--rw=randwrite means exactly what it looks like it means: we’re going to do random write operations to our test files in the current working directory. Other options include seqread, seqwrite, randread, and randrw, all of which should hopefully be fairly self-explanatory.

ques_list[3]={"$nthr","$ncpu","1"}

n=0; for jobs in 1 $ncpu $nthr; do
ques=${ques_list[n]}; let n++
echo "FIO test with size=$size jobs=$jobs ques=$ques"
lgfn="fio-$dev-$size-$jobs-$ques"
fio --name=usbtest --ioengine=posixaio --end_fsync=1 --bs=4k --size=$size \
    --numjobs=$jobs --iodepth=$ques --output=$lgfn --runtime=60
done

exit 0
################################################################################

sudo fdisk -l /dev/${dev}
