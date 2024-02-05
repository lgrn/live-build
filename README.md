# live-build
live-build configuration for building a live debian system with encrypted
persistence

## How to use

Always refer to the [original documentation](https://live-team.pages.debian.net/live-manual/html/live-manual/index.en.html).
It can also be searched for relevant terms (like "persistence") like so:
`site:live-team.pages.debian.net persistence`

### Preparation

Debian is required. Use a VM if necessary.

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

Output is logged to `build.log`

When done, you'll have an .iso file.

### Test ISO file with KVM/QEMU

TODO

### Write ISO to USB stick with encrypted persistence

```bash
dd if=your.iso of=/dev/sdX conv=fsync bs=4M
```

When this is done, you need to create a persistence partition. You can either
choose he size of this yourself, or you can elect to use all remaining space:

```bash
fdisk /dev/sdX <<< $(printf "n\np\n\n\n\nw")
```

In almost all cases, this partition will be `sdX3`. We will now encrypt this
with LUKS:

```bash
cryptsetup --verbose --verify-passphrase luksFormat /dev/sdX3
cryptsetup luksOpen /dev/sdX3 my_usb
```

It's now available as `/dev/mapper/my_usb`, so let's format and label it:

```bash
mkfs.ext4 -L persistence /dev/mapper/my_usb
e2label /dev/mapper/my_usb persistence
```

Finally, mount it so we can create `persistence.conf` on it before closing:

```bash
mkdir -p /mnt/my_usb
mount /dev/mapper/my_usb /mnt/my_usb
echo "/ union" | sudo tee /mnt/my_usb/persistence.conf
umount /dev/mapper/my_usb
cryptsetup luksClose /dev/mapper/my_usb
```

#### Why it works

Because of the `persistence` kernel boot options set in `auto/config`, the ISO
image will by default look for encrypted LUKS partitions on the USB stick and
attempt to decrypt them. Because of the labels and the conf file , it will be
used as persistence when discovered as such (after decryption).

## Configuration

This repo is based on
[images/standard](https://salsa.debian.org/live-team/live-images/-/tree/debian/images/standard?ref_type=heads)
with only minor changes made to the following files:

* `auto/config` to customize things like boot parameters and distro
* `config/package-lists/my.list.chroot` to add additional packages, namely
  gnome, firefox and non-free wireless firmware packages.
