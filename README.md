## Porteus Linux live USB bootable installer

It creates a bootable USB with 512MB of persistence

- Porteus root password: **toor**

- Background image source: [Newsweek](https://www.newsweek.com/government-report-new-space-race-nasa-china-1736843)

- Usage: `bash porteus-usb-install.sh /path/file.iso [/dev/]sdx [it]`

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

USB stick: [Samsung FIT+ 64GB](https://ssd-tester.com/samsung_fit_plus_64gb.html)

- It is very short, preventing USB port damage, essential for long-term use.
- Despite its size it is quite generous in size and pretty fast with USB 3.1.
- Whenever an old laptop/PC hasn't 3.x, exchanging data on 3.1 is faster.

Data encryption:

- It is unnecessary as long as we are using Porteus as testing/rescue distro.
- It is suggested for privacy when an external USB is used for personal needs.
- It is mandatory when we expect, even occasionally, to bring it out with us.

---

### Download mirrors list

- https://porteus.org/porteus-mirrors.html

- https://linux.rz.rub.de/porteus/x86_64/current

---

### Tested with

- [Porteus-MATE-v5.01-x86_64.iso](https://linux.rz.rub.de/porteus/x86_64/current/Porteus-MATE-v5.01-x86_64.iso)  (mainly)

- [Porteus-LXQT-v5.01-x86_64.iso](https://linux.rz.rub.de/porteus/x86_64/current/Porteus-LXQT-v5.01-x86_64.iso)
