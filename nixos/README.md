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
