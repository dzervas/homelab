# Runbooks for the infra

## Longhorn Deleted PV

This is the case where the whole PV got deleted from the cluster, not just the PVC.
First of all, kill the server(s) that host the replicas as soon as possible
using:

```bash
echo o > /proc/sysrq-trigger
```

```bash
https://releases.ubuntu.com/24.04.1/ubuntu-24.04.1-live-server-amd64.iso

console=tty0 console=ttyS0,115200n8

sudo -i
curl https://github.com/dzervas.keys >> .ssh/authorized_keys

apt-get install extundelete ext4magic testdisk
```

Oracle:

Go to the instance > more > create custom image. Then Export the custom image
to a bucket as QCOW2 (might need to create one). Then download the resulting object
from the bucket.

```bash
qemu-img info fra1.img
qemu-img convert fra1.qcow2 fra1.raw
sfdisk -l -uS fra1.raw
Disk fra1.raw: 200 GiB, 214748364800 bytes, 419430400 sectors
Units: sectors of 1 * 512 = 512 bytes
Sector size (logical/physical): 512 bytes / 512 bytes
I/O size (minimum/optimal): 512 bytes / 512 bytes
Disklabel type: gpt
Disk identifier: 26F2B8E0-A56D-49D2-8329-9BFA11823538

Device      Start       End   Sectors   Size Type
fra1.raw1  206848 419430366 419223519 199.9G Linux filesystem
fra1.raw15   2048    204800    202753    99M EFI System

Partition table entries are not in disk order.
dd if=fra1.raw of=fra1p1.raw skip=206848 count=419223519
```
