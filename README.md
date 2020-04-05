# HomeLab

A home server provisioned by ansible to run Hashicorp Consul, Nomad & Vault.
Various services are defined ([terraform/nomad](terraform/nomad)).

Local certificates are signed by Let's Encrypt - don't worry, they're not
exposed to the internet, we sign every subdomain using the DNS-01 challenge.

Info on how that works below.

## Setup

Create an inventory at `~/.homelab/inventory.ini` like:

```ini
[server]
192.168.0.10
```

And copy the default config `server.yml` to `~/.homelab` directory.
It's documented.

```bash
cd ansible
ansible-playbook server.yml
```

If you want to prompt for privilege escalation password (su/sudo) use
the flag `-K`.

Now consul is ready - nomad & vault need some work.

First of all, all services listen on localhost (for security reasons),
so let's forward them for them to be accessible
(fire that in a separate terminal, let it run throughout the setup):

```bash
ssh -NL 127.0.0.1:4646:127.0.0.1:4646 -L 127.0.0.1:8200:127.0.0.1:8200 -L 127.0.0.1:8500:127.0.0.1:8500 <server_ip>
```

Now lets do the initial setup:

1. Access [vault](http://127.0.0.1:8200) and set it up.
2. Get the consul master token ___secret___: `ssh <server_ip> consul acl bootstrap` (Store it somewhere safe OFC)
3. In `~/.homelab/server.yml` set `homelab_consul_token` to the above and `homelab_encrypt` to `ssh <server_ip> grep encrypt /data/consul/config/config.json` (the string matched)
