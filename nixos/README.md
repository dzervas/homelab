# NixOS node setup

## srv1: Raspberry Pi 4 SD image

Build on an x86_64 Linux host with KVM available. Disko creates the actual
LVM/F2FS layout inside a VM; ARM installation commands run through binfmt.
Do **not** use `nixos-generate -f sd-aarch64`: its plain ext4 image does not
match this host's filesystems.

```bash
set -o pipefail
nix build ./nixos#nixosConfigurations.srv1.config.system.build.diskoImages -o ./srv1.sd
zstdcat srv1.sd/root.raw.zst | sudo dd bs=4M status=progress conv=fsync oflag=direct of=/dev/sdX
```
### Expand the card manually over SSH

The initial thin pool is small. Expand it before scheduling storage workloads.
Run as root on the Pi, after confirming `/dev/mmcblk0` is the boot card:

```bash
nix shell nixpkgs#gptfdisk nixpkgs#cloud-utils nixpkgs#lvm2
lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINTS
sgdisk -e /dev/mmcblk0       # Move the backup GPT to the end of the card.
growpart -u on /dev/mmcblk0 2     # Extend only the final LVM partition.
lsblk -o NAME,SIZE          # Verify the kernel sees the larger partition.
```

If the kernel still reports the old partition size, reboot before continuing.
Then, in the same tool shell:

```bash
pvresize /dev/mmcblk0p2
vgs
lvextend -l +99%FREE mainpool/thinpool  # Leave VG space for metadata/maintenance.
lvextend -L 200G mainpool/longhorn # Leave some room for containerd stuff
resize2fs /dev/mapper/mainpool-longhorn
lvs -a -o lv_name,lv_size,pool_lv,data_percent,metadata_percent
```

Longhorn starts at 8 GiB; growing the pool does not grow the LV. To enlarge
it too, use `lvextend -r -L <new-size> /dev/mainpool/longhorn`.

## Fresh install

```bash
export TARGET_HOST=<dns or ip>
export TARGET_HOSTNAME=<hostname (without fqdn)>
nixos-anywhere --flake ./nixos#$TARGET_HOSTNAME --target-host $TARGET_HOST --generate-hardware-config nixos-generate-config ./hosts/$TARGET_HOSTNAME.nix
# It might fail, that's fine
nixos-anywhere --flake ./nixos#$TARGET_HOSTNAME --target-host $TARGET_HOST
```

After it's done, ssh to the host and:

```bash
touch /etc/wireguard-privkey && chmod 400 /etc/wireguard-privkey && wg genkey > /etc/wireguard-privkey
systemctl restart wireguard-wg0
touch /etc/k3s-token && chmod 400 /etc/k3s-token && vim /etc/k3s-token
# paste the token
```

## Migrate k3s node to nixos

```bash
k drain $TARGET_HOSTNAME --ignore-daemonsets
```

SSH to the target:

```bash
crictl rmi --all
systemctl stop k3s
tar cpf k3s-migrate.tar.gz /var/lib/rancher/k3s /etc/rancher/node/password /var/lib/zerotier-one/identity.* /var/lib/zerotier-one/authtoken.secret
```

Download it locally

```bash
scp $TARGET_HOST:k3s-migrate.tar.gz .
```

Do the installation normally

```bash
scp k3s-migrate.tar.gz $TARGET_HOST:~/
```

SSH to the target and:

```bash
cd /
systemctl stop k3s.service
rm -rf /etc/rancher/node/password /var/lib/rancher/k3s
tar xf ~/k3s-migrate.tar.gz
systemctl start k3s.service
```

And lastly:

```bash
k uncordon $TARGET_HOSTNAME
```

## Offline root fs tinkering if the host boots

Just whip up a kexec nixos system:

```bash
nixos-anywhere --target-host <host> --flake ./nixos --phases kexec
```

