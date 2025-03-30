## Porteus live USB bootable installer

It creates a bootable USB with 128MB for persistence.

- Porteus root password: **toor**

- Background image source: [Newsweek](https://www.newsweek.com/government-report-new-space-race-nasa-china-1736843)

- Usage: `bash porteus-usb-install.sh /path/file.iso [/dev/]sdx [it] [--ext4-install]`
   - When everything is already local and updated as per the latest ISO.
   - Long option creates a USB bootable installation instead of a LIVE.
   - Performances LIVE vs EXT4 may greatly vary depending on USB stick.
   - First EXT4 installation boot is **slow** because lazy mkfs options.
   - Some USB2 sticks allow legacy boot only, it may be disabled in BIOS.

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

How long does it take to prepare such a USB 2.0 stick? Less than 120 seconds (since v0.3.3, less than 40s) with 128MB of persistence. Almost all the time is spent in writing the USB, hence that matters is the writing speed and data size.

#### About other buses/ports

An alternative to using a USB pendrive, is leveraging the internal u/SD reader, if it exists to save a USB port. In this case, it is useful to keep in mind that such embedded readers, like the one included into the Thinkpad X201, is limited by the USB version bus bandwidth.

So, it does not provide any advantages over the USB bus, and the same **might** apply also to the ExpressCard/54 slot using an adapter working as an USB device and limited to 133 MB/s on those rare units that have the USB 3.0. Instead, using the ExpressCard/54 with a PCIe adapter it can work at 250 MB/s which is near the 300M MB/s available on the internal SATA2.

In conclusion, a USB 2.0 laptop will be limited at 480 Mbps in accessing storage devices unless SATA2 or EC54/PCie is used. And in this particular case, the adoption of a ExpressCard/54 USB 3.0 adapter can provide that upgrade needed to leverage faster USB devices.

---

### Huston, we have a problem

On 25th March 2025, all Porteus mirrors are presenting zeroed sha256sums.txt, and it is quite a thing!

![sha256sum files missing](img/porteus-iso-sha256sum-compromised.png)

- Source: [A post of mine on forum.porteus.org](https://forum.porteus.org/viewtopic.php?p=102450#p102450)

Without those files the scripts in this project cannot work and making them working is unacceptably insecure.

---

### Default choices

This is a list of system choices that I made in advance for customising the Porteus **moonwalker** edition.

1. The script is not executable by default, hence it requires to be run by a shell. An extra caution: even if it requires root password, the session could be already on sudo or root.

2. I [decided](https://chatgpt.com/share/67e01ea8-a0f4-8012-9178-48d1c76337e9) to go without a journal within the persistent loop file because it is saved on a VFAT. It is faster and stresses the USB key less, and thus increases its durability.

3. The size of the first partition into the MBR is too big to fit a common 1GB usbkey which is usually 10^9 bytes eq. to 1.953.125 blocks. Thus a 2GB usbkey is the min. required.

4. The size of the persistent loop file has been set to 128Mb in such a way there will be 430MB c.a. of free space to install optional modules. As much as the whole Porteus base.

5. With `--ext4-install`, the EFI boot partition size is 16 MB and remains 4 MB free by default with Porteus 5.01. It contains iso/syslinux and lilo stuff, the kernel and initrd.

6. The file `cmdline.txt` contains options for kernel line, by default it sets `noswap` and activate the IOMMU in passtrought mode for those machine that support it in full. The swap is not just a bottleneck but a performance killer, let the users deal with it manually when they desperately need it, only.

---

### Suggested choices

A set of choices that every Porteus user is going to face soon or later. The suggestions are not intended to be *good for all* but as a reasonable starting point for those whom are not technically skilled and might be puzzled by the great amount of choices that also live distro like Porteus can offer.

Some are *matter of taste* and in that cases, the most widespread options (or likely the most suitable similars) are chosen in order to let the beginners have as much large user-base as possible for asking support. Statistically speaking, giving them the highest chance to find someone that had solved those issues they most probably may face.

Porteus version: **MATE**

- Ubuntu is one of the most wide-spread and well-known Linux distributions.
- Ubuntu uses Gnome3 and the 2nd most appreciated flavour is the Mate one.
- Mate is based on Gnome2 and old PCs running Linux were usually adopting it.

USB stick: **Samsung FIT plus** [64GB](https://ssd-tester.com/samsung_fit_plus_64gb.html)

- It is very short, preventing USB port damage, essential for long-term use.
- Despite its size it is quite generous in size and [pretty fast](img/1st-topperf-branded-nano-usbstick.png) with USB 3.1.
- Whenever an old laptop/PC hasn't 3.x, exchanging data on 3.1 is faster.
- Check in the ThinkPaa X201 section [about](#about-other-busesports) using an micro-SD card, instead.

Full installation:

- Using `--ext4-install` implies that writing data is going to be a routine.
- The [256GB](https://ssd-tester.com/samsung_fit_plus_256gb.html) for a physical EXT4 persistence is 3x faster in WR on USB 3.x.
- If SATA2+ is available, at half of the price a 240GB+ [SSD](https://ssd-tester.com/sata_ssd_test.php?sort=250+GB) is another 3x faster.
- If USB 3.x then a SATA [adapter](https://raw.githubusercontent.com/robang74/porteus-usb-installer/refs/heads/main/img/usb3-sata3-adapter-with-plastic-case.webp) w/ABS case ($4) is faster, cheaper & easier.

Data encryption:

- It is unnecessary as long as we are using Porteus as testing/rescue distro.
- It is suggested for privacy when an external USB is used for personal needs.
- It is mandatory when we expect, even occasionally, to bring it out with us.

Download mirrors list:

- [porteus.org/porteus-mirrors.html](https://porteus.org/porteus-mirrors.html)

- [porteus-mirror-allhttps.txt](porteus-mirror-allhttps.txt) (local)

Installation tested:

- [Porteus-MATE-v5.01-x86_64.iso](https://linux.rz.rub.de/porteus/x86_64/current/Porteus-MATE-v5.01-x86_64.iso) (mainly)

- [Porteus-LXQT-v5.01-x86_64.iso](https://linux.rz.rub.de/porteus/x86_64/current/Porteus-LXQT-v5.01-x86_64.iso) (for QT lovers)

---

### Usage, quick & dirty

This little script downloads and immediately puts in execution the network installation . Which download the MATE version of the official Porteus ISO and a compressed archive of this repository chosen from [tags](https://github.com/robang74/porteus-usb-installer/tags) available. Check the [TODO](TODO) for knowing in advance about development and possible shortcomings.

```
mkdir -p usbtest; cd usbtest
tagver="v0.3.3" # To replace with the latest available in tags
rawurl="https://raw.githubusercontent.com/robang74"
rawurl="$rawurl/porteus-usb-installer/refs/tags/$tagver"
rawurl="$rawurl/porteus-net-install.sh"
DEVEL=0 # bash <(wget -qO- $net_inst_url)
```

At this point everything is ready to write the USB stick for having the desidered installation. It can be done by the USB installation script which requires `root` privileges. Because mistakes happen, the most safe way to proceed is to create a bootable USB stick in the way you're used to and transfer all the stuff into another USB stick.

Booting Porteus in RAM-only (Flash) mode, it will be possible to execute the scripts on the 2nd USB stick to install on the first which will be erased, or another one. In the future a 2nd USB key would not be necessary. A specific script will do everything in a RAM-only (Flash) running Porteuse, zeroing every risk.

```
mkdir -p usbtest; cd usbtest
wget -qO- http://alturl.com/ggvaa | tar xvz
mv porteus-usb-installer-main moonwalker
DEVEL=0 # bash moonwalker/porteus-net-install.sh
# or to simulate a remote call
# DEVEL=0 # bash <(cat moonwalker/porteus-net-install.sh)
```

If &ndash; **for you** &ndash; the shell code above does nothing, then it is ok in that way: do not use it. ;-)

---

### Future improvements

The script requires `bash` because it uses bashims. This should change in future, because I want to make it working also with busybox `a/sh`. Plus, before moving to try it on different systems than my laptop, I wish to create a net-installer that downloads all my stuff and the ISO and does the magic. This make sense because Porteus has the all-in-memory mode so we can download the ISO and write it directly on as USB:

- `wget -O- $url | sudo dd bs=1M of=/dev/sdx`

Then we can put that USB into a laptop/PC, boot in all-in-memory mode, clone the git and re-write that USB within a safe environment. Which is the reason because `dd` uses the `seek` option creating a virtual file that does not waste space, in evoluted filesystem that allows holes into files, at least.

When that file is copied into the VFAT32, then the holes are filled with zeros, hopefully. In fact, `cp` is supposed to not access the underlying physical device unless the kernel allocated blocks into the file instead of holes. This implies that we do not need extra 512Mb of free memory (or 128Mb per the last v0.2.5 version) to create those files but much less (c.a. 10Mb). While `/boot` `/syslinux` and `/porteus` folders are - supposedly - loaded in RAM, so we can rewrite the USB stick reading from the RAM filesystem.

If you would like to know more about future planning, read the [BOFH as lifestyle manifesto](bofh-as-life-style-manifesto.txt).

---

### On-demand USB live image

Why in 2025 we are still busy with ISO? Instead of having an on-demand USB bootable maker? What is necessary to have it? Under the DIY PoV, every device that makes sense to use despite its age is currently able to create an USB bootable (or install into an internal storage unit) a Linux live. Every device like an X220 can be turned into a Kiosk for such a task.

So, the first thing we need is a lightweight graphical - even running of framebuffer - operative system like [TinyCore](http://tinycorelinux.net/downloads.html). A lightweight browser like [Dillo](https://dillo-browser.github.io) would be enough to let the user cope with a simple HTML form that guides them to configure on-demand the installation.

At this point, we need to have a list of core components and a recipe to put all together. Which is the reason I developed this set of scripts. The next step is to provide a network connection to the Kiosk and while Wi-Fi is the easiest way especially using a smartphone like a router, usually the Wi-Fi card is a pain because proprietary firmware.

However, those USB dongle based on RTL8188 at 150 MBit/s - which were usually to find in Raspberry Pi kits - are almost universally supported by Linux. Having two USB 2.0 ports available is not a strict constraints: in one the Wi-Fi dongle ($2) and in the other a USB stick ($12) and the installation can start. Considering $1 of postal stamp, it sum-ups to $15.

---

### Embedded systems

Are you more of an embedded guy/girl? In this case, I suggest [TinyCore](http://tinycorelinux.net/) Linux rather than Porteus which is more suitable for old hardware and kiosk systems. In particular, [TinyCore Editor](https://github.com/robang74/tinycore-editor) can serve you as a non-certifiable by design but functioning proof-of-concept system editor.

---

### Copyright

(C) 2025, Roberto A. Foglietta &lt;roberto.foglietta@gmail.com&gt;, licensed under BSD 3-clauses terms.

**Note**: the boot screen image, also used for background, is included here as per *fair-use* terms, only.
