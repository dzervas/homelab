# NixOS node setup

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
systemctl restart wg-quick-wg0
zerotier-cli join <network id>
touch /etc/k3s-token && chmod 400 /etc/k3s-token && vim /etc/k3s-token
# paste the token
```

## Migrate k3s node to nixos

```bash
k drain $TARGET_HOSTNAME --ignore-daemonsets
```

SSH to the target:

```bash
systemctl stop k3s
tar cpf k3s-migrate.tar.gz /var/lib/rancher/k3s /etc/rancher/node/password
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
