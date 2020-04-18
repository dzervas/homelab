# HomeLab

A home server provisioned by ansible to run docker-compose.

Local certificates are signed by Let's Encrypt - don't worry, they're not
exposed to the internet, we sign every subdomain using the DNS-01 challenge
with CloudFlare.

In order to have access to HTTPS resources, the local network DNS should be
redirecting all the subdomains of your domain to the server.

For example if your domain is `home.lab.net`, `*.home.lab.net` AND
`home.lab.net` should resolve to your server's IP. This is required as
there is no way to get signed certificates by Let's Encrypt for non-internet
TLDs. You have to buy a regular domain (you can even find a domain ~3$/year)
and use it to access your services.

## Setup

Create a CloudFlare account, add your domain or subdomain and follow
CloudFlare's guide. It's very easy. Create a DNS API key that has
`Zone/Zone/Read` and `Zone/DNS/Edit` permissions and access to all zones.

Create an inventory at `~/.homelab/inventory.ini` like:

```ini
[server]
192.168.0.10
```

Copy the default config `vault.example.yml` to `vault.yml` and change it
according to your needs, it's documented.

```shell script
ansible-playbook server.yml
```

If you want to prompt for privilege escalation password (su/sudo) use
the flag `-K`.

All the services should be up and accessible!

You can start by `auth.<domain>` to check that authentication works correctly
(required in many places).

## NVidia Drivers for hashcat

Hashtopolis is set up and some configuration for its client is required.
SSH to the server and do the following:

```shell script
apt install ubuntu-drivers-common
ubuntu-drivers devices
apt install nvidia-driver-<recommended above> ocl-icd-libopencl1 nvidia-cuda-toolkit
rmmod nouveau
echo blacklist nouveau > /etc/modprobe.d/blacklist-nouveau.conf
modprobe nvidia
```

Open a tmux session or something and run the hashtopolis client, as described
in the web UI.

NOW you're good to go!

## Using gopass with ansible-vault

Create the following files in the root directory (they are git ignored):

`ansible.cfg`
```ini
[defaults]
vault_identity_list = ansible@vault.sh
```

`vault.sh`
```shell script
#!/bin/sh
# Of course any other command that spits the password will work
gopass show "my/vault/password/path"
```

Now to copy the default `vault.example.yml`:

```shell script
ansible-vault encrypt --output vault.yml vault.example.yml
```

Edit it with `ansible-vault edit vault.yml`