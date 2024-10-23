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
