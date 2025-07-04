# live-build

live-build configuration for building a live debian system with encrypted
persistence.

## Overview of steps involved

- Create an ISO using `live-build`.
- Write ISO to USB
- Boot from that USB, physically or in VM
- Set up an encrypted persistence partition (LUKS)

## 1 – Introduction

`live-build` is, according to their own documentation:

> A collection of scripts used to build customized live systems

Always refer to the [original documentation](https://live-team.pages.debian.net/live-manual/html/live-manual/index.en.html)
when looking for answers on how `live-build` works. Prefix your
googling with `site:live-team.pages.debian.net` for doc results only.

### 1.1 – Building the ISO

If you don't want to build the ISO yourself, grab one from the releases
section on github.

> [!IMPORTANT]
> Debian is required for this guide. Use a VM if necessary, run as root.

Install required packages:

```bash
apt install live-build git
```

Create a directory and initialize a configuration from (this) repo:

```bash
mkdir live-build && cd live-build
lb config --config https://github.com/lgrn/live-build.git
```

Trigger a build (possibly do `lb clean` first):

```bash
lb build
```

Full output is available in `build.log`, the file is removed on every
`lb clean`

Build times vary heavily, but you can expect at least 15-30 minutes. If the
build succeeded, you should now have an ISO:
`live-image-amd64.hybrid.iso`

### 1.1 – Boot from ISO only

If you wish the test the ISO without persistence, you can easily boot
from it:

```bash
qemu-system-x86_64 -cdrom live-image-amd64.hybrid.iso \
-m 4096 -smp 6 -accel kvm -cpu host
```

## 2 – Write ISO and persistence to USB memory stick

Assumptions:

- You already have an ISO from section 1, or downloaded from github.
- You have a USB drive.

> [!CAUTION]
> `dd` is called "disk destroyer" for a reason. Make sure `sdX` below really,
> really refers to the USB stick you want to write to. Then make sure again.

Write the ISO to the USB device (sdX):

```bash
dd if=live-image-amd64.hybrid.iso of=/dev/sdX conv=fsync bs=4M status=progress
```

At this point, your USB stick is already capable of booting, but it lacks
persistence. To add a new partition, use the following hacky one-liner to
simply create a new partition where the first existing one ends, using all
available free space that is left on the device:

```bash
fdisk /dev/sdX <<< $(printf "n\np\n\n\n\nw")
```

If you want to manually decide how large the partition should be, you must run
`fdisk` manually instead: `n`, `p`, `[enter]`, `[enter]`, `+2G`, `w`.

In almost all cases, this new partition will be `sdX3`.

### 2.1 – Create encrypted persistence

```bash
# encrypt, open, format and label device
cryptsetup --verbose --verify-passphrase luksFormat /dev/sdX3
cryptsetup luksOpen /dev/sdX3 usb
mkfs.ext4 -L persistence /dev/mapper/usb
e2label /dev/mapper/usb persistence

# mount to place persistence.conf
mkdir -p /mnt/usb
mount /dev/mapper/usb /mnt/usb

# choose your kind of persistence:

# 1. everything!
# (may save unnecessary stuff like cache to encrypted storage)
# NOTE: /var/cache can be especially bad
echo "/ union" | tee /mnt/usb/persistence.conf

# 2. tailored:
# things may break, but you can add more folders later
tee /mnt/usb/persistence.conf <<EOF
/home union
/etc union
/usr union
/var/lib union
EOF

# unmount and close
umount /dev/mapper/usb
cryptsetup luksClose /dev/mapper/usb
```

Done.

Consider pros and cons: `/ union` in `persistence.conf` means that
everything is persistent, while `/home union`would mean everything is
discarded except changes in `/home`. These have different and obvious
implications for IO traffic.

The USB is ready to go. You can now either:

1. Reboot from the USB physically.
1. As below, boot a VM from the USB device.

## 3 – Booting USB stick with QEMU

To save some time, you may want to interface directly with the USB
stick through QEMU rather than having to physically reboot multiple
times.

### 3.1 – QEMU flags explained

- `-boot d`: boot from cdrom device (not used)
- `-cdrom [string]`: path to ISO file, used as cdrom device (not used)
- `-m [int]`: megabytes of memory
- `-smp [int]`: virtual cpus
- `-drive [string]`: use this as primary disk

### 3.2 – QEMU USB boot

```bash
qemu-system-x86_64 -drive file=/dev/sda,format=raw,media=disk \
-m 4096 -smp 6 -accel kvm -cpu host
```

> [!IMPORTANT]
> In a virtual environment, the disk will not be recognized as a USB
> thumbdrive. You **must** therefore modify the boot parameters and
> remove `persistence-media=removable-usb`.

After unlocking the LUKS encrypted partition on boot, you are free to
customize your environment before backing up your persistence.

## 4 – Backup

When you are happy with the state of your environment, it's probably a
good idea to back it up. The easiest way that I've found of doing this
is to simply allow your regular Linux environment to unlock and mount
the encrypted partition.

In most desktop environments, you'll be prompted to decrypt it as soon
as your USB is inserted. After it's unlocked, you can usually find it
at something like `/media/your_user/persistence`, and since this
appears like any regular mounted ext4 partition, you can back it up
however you see fit, for example with [restic](https://restic.net/)

## 4.1 – Restoring from backup

If you have created a new USB stick with an encrypted but empty
persistence partition, you simply need to unlock it, mount it and move
the files over from your backup.

## 5 – Technical description, or why it works

Because of kernel boot options set in `auto/config`, the ISO image will by
default look for encrypted LUKS partitions on the USB stick and attempt to
decrypt them. Here is what each of the persistence settings mean:

- `persistence`: attempt to boot with persistence (look for partitions)
- `persistence-encryption=luks`: attempt to decrypt any found LUKS partitions
- `persistence-media=removable-usb` only look for LUKS partitions on removable
  USB devices

If you wish to change these values permanently, they must be changed in
`auto/config` before building. They can also be changed temporarily on each
boot.

## 6 – Postscript

This repo is based on
[images/standard](https://salsa.debian.org/live-team/live-images/-/tree/debian/images/standard?ref_type=heads)
with only minor changes made to the following files:

* `auto/config` to customize things like boot parameters and distro
* `config/package-lists/my.list.chroot` to add additional packages, namely
  gnome, firefox and non-free wireless firmware packages.
* `config/hooks/normal/` to run certain commands before creating the ISO.
* `config/includes.chroot/` corresponds to the root of the file system,
  use this to inject configuration files etc.

> [!CAUTION]
> **Do not** include sensitive information of any kind in
> `includes.chroot`, the root file system of `live-build` is **not
> encrypted**. All sensitive information must go into LUKS-encrypted
> persistence later.
