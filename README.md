## Porteus live USB bootable installer

It creates a bootable USB with 128MB for persistence.

- Porteus root password: **toor**

- Background image source: [Newsweek](https://www.newsweek.com/government-report-new-space-race-nasa-china-1736843)

- Usage: `bash porteus-usb-install.sh /path/file.iso [/dev/]sdx [it] [--ext4-install]`
   - when everything is already local and updated as per the latest ISO.
   - long option creates a USB bootable installation instead of a LIVE.

- Usage: `bash porteus-net-install.sh [<type> <url> <arch> <vers>] [/dev/sdx] [it]`
   - when downloading the ISO and retrieving this repo scripts is needed.

- Usage: `bash porteus-mirror-selection.sh [--clean]`
   - check among the available mirrors the fastest one for downloading.  

The v0.2.0 has been reported that it works also for [PorteuX](https://github.com/porteux/porteux) but I did not test it and I am not granting the compatibility for the future.

---

### Persistence vs Installation

<div align="justify">

> Persistence means that any changes you make to the system (like installing software, saving files, or changing settings) will be saved and available the next time you boot from the USB drive. Without persistence, the system would revert to its original state each time. Installation is a process designed to create a permanent and independent operating environment while a [LIVE](https://en.wikipedia.org/wiki/Live_USB) is running into the computer's RAM, mainly. This allows users to run an OS without modifying the host system's storage. Persistence, is a bridge between the two concepts. &ndash;&nbsp;Gemini&nbsp;2

</div>

---

### Preview on 13yo laptop

The ThinkPad X220 was released in April 2011 and was produced until mid-to-late 2012, when it was replaced by the ThinkPad X230. Today, it is a 13yo device and can be bought for around $100 as refurbished or used unit, only. Old but not obsolete.

In fact, it supports SATA2 SSD and 16GB of DDR3 RAM despite its specification indicates 8GB as maximum. While models with the i7-2620M typically include USB 3.0 support, also. However, usually it comes with 4GB of RAM, a 2.5" SATA HDD and USB 2.0, only. 

Porteus 5.01 Mate booting from an old SanDisk Cruzer Fit 32GB USB 2.0 and running on an ultra-old Thinkpad X220 equipped with 4GB of RAM. The storage stick is inserted in the USB 2.0 port, on the bottom left angle, and it is so short that it cannot even be seen without checking for it specifically for it.

<div align="center"><img src="img/x220-porteus-mate-boot-and-desktop.jpg" width="100%"></div>

How long does it take to prepare such a USB 2.0 stick? Less than 120 seconds with 128MB of persistence. Almost all the time is spent in writing the USB, hence that matters is the writing speed and data size.

---

### Default choices

1. The script is not executable by default, hence it requires to be run by a shell. An extra caution: even if it requires root password, the session could be already on sudo or root.

2. I decided to go without a journal within the persistent loop file because it is saved on a VFAT. It is faster and stresses the USB key less, and thus increases its durability.

3. The size of the first partition into the MBR is too big to fit a common 1GB usbkey which is usually 10^9 bytes eq. to 1.953.125 blocks. Thus a 2GB usbkey is the min. required.

4. The size of the persistent loop file has been set to 128Mb in such a way there will be 430MB c.a. of free space to install optional modules. As much as the whole Porteus base.

---

### Suggested choices

Porteus version: **MATE**

- Ubuntu is one of the most wide-spread and well-known Linux distributions.
- Ubuntu uses Gnome3 and the 2nd most appreciated flavour is the Mate one.
- Mate is based on Gnome2 and old PCs running Linux were usually adopting it.

USB stick: **Samsung FIT plus** [64GB](https://ssd-tester.com/samsung_fit_plus_64gb.html)

- It is very short, preventing USB port damage, essential for long-term use.
- Despite its size it is quite generous in size and pretty fast with USB 3.1.
- Whenever an old laptop/PC hasn't 3.x, exchanging data on 3.1 is faster.

Full installation:

- Using `--ext4-install` implies that writing data is going to be a routine.
- The [256GB](https://ssd-tester.com/samsung_fit_plus_256gb.html) for a physical EXT4 persistence is 3x faster in WR on USB 3.x.
- If SATA2+ is available, at half of the price a 240GB+ [SSD](https://ssd-tester.com/sata_ssd_test.php?sort=250+GB) is another 3x faster.

Data encryption:

- It is unnecessary as long as we are using Porteus as testing/rescue distro.
- It is suggested for privacy when an external USB is used for personal needs.
- It is mandatory when we expect, even occasionally, to bring it out with us.

---

### Download mirrors list

- https://porteus.org/porteus-mirrors.html

- https://linux.rz.rub.de/porteus/x86_64/current

---

### Tested installing

- [Porteus-MATE-v5.01-x86_64.iso](https://linux.rz.rub.de/porteus/x86_64/current/Porteus-MATE-v5.01-x86_64.iso)  (mainly)

- [Porteus-LXQT-v5.01-x86_64.iso](https://linux.rz.rub.de/porteus/x86_64/current/Porteus-LXQT-v5.01-x86_64.iso)

---

### Future improvements

The script requires `bash` because it uses bashims. This should change in future, because I want to make it working also with busybox `a/sh`. Plus, before moving to try it on different systems than my laptop, I wish to create a net-installer that downloads all my stuff and the ISO and does the magic. This make sense because Porteus has the all-in-memory mode so we can download the ISO and write it directly on as USB:

- `wget -O- $url | sudo dd bs=1M of=/dev/sdb`

Then we can put that USB into a laptop/PC, boot in all-in-memory mode, clone the git and re-write that USB within a safe environment. Which is the reason because `dd` uses the `seek` option creating a virtual file that does not waste space, in evoluted filesystem that allows holes into files, at least.

When that file is copied into the VFAT32, then the holes are filled with zeros, hopefully. In fact, `cp` is supposed to not access the underlying physical device unless the kernel allocated blocks into the file instead of holes. This implies that we do not need extra 512Mb of free memory (or 128Mb per the last v0.2.5 version) to create those files but much less (c.a. 10Mb). While `/boot` `/syslinux` and `/porteus` folders are - supposedly - loaded in RAM, so we can rewrite the USB stick reading from the RAM filesystem.

If you would like to know more about future planning, read the [BOFH as lifestyle manifesto](bofh-as-life-style-manifesto.txt).

---

### Embedded systems

Are you more of an embedded guy/girl? In this case, I suggest [TinyCore](http://tinycorelinux.net/) Linux rather than Porteus which is more suitable for old hardware and kiosk systems. In particular, [TinyCore Editor](https://github.com/robang74/tinycore-editor) can serve you as a non-certifiable by design but functioning proof-of-concept system editor.

---

### Copyright

(C) 2025, Roberto A. Foglietta &lt;roberto.foglietta@gmail.com&gt;, licensed under BSD 3-clauses terms.

**Note**: the boot screen image, also used for background, is included here as per *fair-use* terms, only.
