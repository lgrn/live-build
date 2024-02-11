# live-build

live-build configuration for building a live debian system with encrypted
persistence.

## Overview of steps involved

- Create an ISO using `live-build`.
- Write ISO to USB
- Boot from that USB, physically or in VM
- Set up an encrypted persistence partition (LUKS)

## 1 `live-build`

`live-build` is, according to their own documentation:

> A collection of scripts used to build customized live systems

Always refer to the [original documentation](https://live-team.pages.debian.net/live-manual/html/live-manual/index.en.html)
when looking for answers on how `live-build` works.

> [!TIP]
> Prefix your googling with `site:live-team.pages.debian.net` for doc results only.

### 1.1 Building the ISO

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

> [!NOTE]
> Full output is available in `build.log`, the file is removed on every `lb clean`

Build times vary heavily, but you can expect at least 15-30 minutes. If the
build succeeded, you should now have an ISO: `live-image-amd64.hybrid.iso`

## 2 Booting ISO file with KVM/QEMU

> [!NOTE]
> Booting the ISO without writing it to USB first may be useful for testing. If
> you don't care, skip to section 3.

### 2.1 QEMU flags

- `-boot d`: boot from cdrom device
- `-cdrom [string]`: path to ISO file, used as cdrom device
- `-m [int]`: megabytes of memory
- `-smp [int]`: virtual cpus
- `-drive [string]`: takes `format=` and `file=` comma separated

### 2.2 QEMU ISO boot

```bash
qemu-system-x86_64 -boot d -cdrom live-image-amd64.hybrid.iso \
-m 4096 -smp 4 -accel kvm
```

### 2.3 Persistent QCOW file in QEMU (for testing)

> [!NOTE]
> TODO: **This is only for testing purposes**, it is not part of setting up USB
>persistence. There's currently no tested and working way to write existing
> QCOW persistence to the USB that I know of. If you've tested something and it
> works, let me know.

```bash
qemu-img create -f qcow2 persistence.qcow2 2G
```

Now let's set up the QCOW as an encrypted persistence partition. As root:

```bash
# load nbd kernel module
modprobe nbd max_part=4

# attach the device
qemu-nbd --connect=/dev/nbd0 persistence.qcow2

# encrypt, open, format and label device
cryptsetup --verbose --verify-passphrase luksFormat /dev/nbd0

# verify the device
cryptsetup luksDump /dev/nbd0 | head
LUKS header information
Version:       	2
(...)

# open, format and label
cryptsetup luksOpen /dev/nbd0 qcow
mkfs.ext4 -L persistence /dev/mapper/qcow
e2label /dev/mapper/qcow persistence

# mount to place persistence.conf
mkdir -p /mnt/qcow
mount /dev/mapper/qcow /mnt/qcow
echo "/home union" | tee /mnt/qcow/persistence.conf

# unmount and close
umount /dev/mapper/qcow
cryptsetup luksClose /dev/mapper/qcow

# if you want to use /dev/nbd0 in a VM (below),
# you need to disconnect it first.
qemu-nbd --disconnect /dev/nbd0
```

> [!NOTE]
> When attaching the persistence QCOW with `-drive`, remember to temporarily
> remove `persistence-media=removable-usb` from the boot options, if present,
> as this disk will not show up as a removable USB device.

```bash
qemu-system-x86_64 -boot d -cdrom live-image-amd64.hybrid.iso \
-m 4096 -smp 4 -accel kvm \
-drive format=qcow2,file=persistence.qcow2
```

You should be asked for the passphrase on boot.

This is a good time to set your environment up as you want it, then reboot the
VM and confirm that the changes stick.

When you're happy, you can move on to writing data to USB.

## 3 Write ISO and persistence to USB memory stick

Assumptions:

- You already have an ISO from section 1.
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

### 3.1 Create encrypted persistence

> [!NOTE]
> It's not strictly necessary to do this from within the VM, but it's both
> safer and more convenient to be able to test the persistence without having
> to yank the USB stick between machines.

Start a VM using your physical USB as disk:

```bash
qemu-system-x86_64 -m 4096 -smp 4 -accel kvm -hdb /dev/sdX
```

It will boot without persistence, let's set it up. As root:

```bash
# encrypt, open, format and label device
cryptsetup --verbose --verify-passphrase luksFormat /dev/sdX3
cryptsetup luksOpen /dev/sdX3 usb
mkfs.ext4 -L persistence /dev/mapper/usb
e2label /dev/mapper/usb persistence

# mount to place persistence.conf
mkdir -p /mnt/usb
mount /dev/mapper/usb /mnt/usb
echo "/home union" | tee /mnt/usb/persistence.conf

# unmount and close
umount /dev/mapper/usb
cryptsetup luksClose /dev/mapper/usb
```

> [!NOTE]
> Consider pros and cons: `/ union` in `persistence.conf` means that everything
> is persistent, while `/home union`would mean everything is discarded except
> changes in `/home`. These have different and obvious implications for IO
> traffic.

The USB is now ready to go. You can now either:

1. Simply reboot the VM. In this case, remember to remove
   `persistence-media=removable-usb` from the boot options, as the VM will not
   correctly identify that this is a USB device.
2. Power-off and insert the USB in another PC.

## 4 Technical description, or why it works

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

## 5 Postscript

This repo is based on
[images/standard](https://salsa.debian.org/live-team/live-images/-/tree/debian/images/standard?ref_type=heads)
with only minor changes made to the following files:

* `auto/config` to customize things like boot parameters and distro
* `config/package-lists/my.list.chroot` to add additional packages, namely
  gnome, firefox and non-free wireless firmware packages.
* `config/hooks/normal/` to run certain commands before creating the ISO,
  currently just purging packages to conserve space.
