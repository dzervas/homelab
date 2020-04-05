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

And copy the default config `server.yml` to `~/.homelab` directory. Change it according to your needs, it's documented.

```shell script
cd ansible
ansible-playbook server.yml
```

If you want to prompt for privilege escalation password (su/sudo) use
the flag `-K`.

Now consul is ready - nomad & vault need some work.

First of all, all services listen on localhost (for security reasons),
so let's forward them for them to be accessible
(fire that in a separate terminal, let it run throughout the setup):

```shell script
ssh -NL 127.0.0.1:4646:127.0.0.1:4646 -L 127.0.0.1:8200:127.0.0.1:8200 -L 127.0.0.1:8500:127.0.0.1:8500 <server_ip>
```

I advise using [gopass](https://github.com/gopasspw/gopass) to store the secrets - I'll provide some good-usage
examples as well

Now lets do the initial setup:

1. Access [vault](http://127.0.0.1:8200) and set it up - choose PGP encryption and store the provided keys in gopass (`echo -n "<key>" | base64 -d | gpg -d | gopass insert -f vault-<key-name>-token`)
   - NOTE: The "Key <num>" is used on every vault restart to unseal it and "Master Key" is used to log in 
2. Get the consul master token ___secret___: `ssh <server_ip> consul acl bootstrap` (Store the SecretID in gopass)
3. In `~/.homelab/server.yml` set:
   - `homelab_consul_token` to consul master token
   - `homelab_vault_token` to vault master token (not the "Key X" that is used to unseal the vault)
   - `homelab_encrypt` to `ssh <server_ip> grep encrypt /data/consul/config/config.json` (the string matched)
4. Rerun the `server.yml` playbook
5. Get the nomad master token ___secret___: `ssh <server_ip> nomad acl bootstrap` (Store the SecretID in gopass)
6. Done!

BTW, secure the configs that include secrets on the server (as root):

```shell script
chmod 700 /data/{consul,nomad,vault}
chmod 600 /data/nomad/config/*
```

## Services

Now the whole setup is ready! :)

Lets use our "private cloud" with terraform!

At this point we still need the SSH port forward - we will expose this services using the Let's Encrypt reverse proxy
after terraform is run.

```shell script
cd terraform
CONSUL_TOKEN="$(gopass show -o consul-token)" VAULT_TOKEN="$(gopass show -o vault-master-token)" NOMAD_TOKEN="$(gopass show -o nomad-token)" terraform apply
```

NOW you're good to go!
