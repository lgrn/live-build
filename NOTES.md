# notes

This file contains things that might be useful, but does not belong in
`README`. It's unstructured, so searching is recommended.

## Persistent QCOW file in QEMU (for testing)

While normally not part of setting up encrypted persistence on a USB
stick, you may want to experiment without a USB stick. In these cases,
you can simulate a persistence partition by attaching a QCOW disk instead.

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

# optionally, verify the device
cryptsetup luksDump /dev/nbd0 | head
LUKS header information
(...)

# open, format and label
cryptsetup luksOpen /dev/nbd0 qcow
mkfs.ext4 -L persistence /dev/mapper/qcow
e2label /dev/mapper/qcow persistence

# mount to place persistence.conf
mkdir -p /mnt/qcow
mount /dev/mapper/qcow /mnt/qcow
echo "/ union" | tee /mnt/qcow/persistence.conf

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
