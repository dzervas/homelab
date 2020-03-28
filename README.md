# HomeLab

Deployment of my home infrastructure. Devices:

 - Router (Alix 2 by PCEngines)
 - 2x Managed switches (DGS-1100 by D-Link)
 - A server (my old desktop)

The router runs Mepis Antix (problem with the i586 architecture by Debian)
and the server runs Ubuntu 18.04 LTS.

## Ansible

The router & the server are provisioned using ansible.
The configuration is long (for the router at least), take your time

Create an inventory at `~/.homelab/inventory.ini` like:
(of course setup the router before the server)

```ini
[router]
192.168.0.1

[server]
192.168.0.10
```

And copy the default config `variables.yml` to `~/.homelab` directory.
It's documented.

```bash
cd ansible
ansible-playbook main.yml
```

## Docker

All of the services are hosted on the server and deployed exclusively with
docker-compose. Here is my setup

On the server:

```
useradd -s /bin/bash -g docker -md /var/docker docker
mkdir ~docker/.ssh
cp ~user/.ssh/authorized_keys ~docker/.ssh
```

On your machine:

```
export DOCKER_HOST="ssh://docker@server.lan"
docker network create nginx-proxy
```

### Home Assistant HomeKit

An mDNS reflector is needed. On the server:

```
apt install avahi-daemon
systemctl enable avahi-daemon
```

Edit `/etc/avahi/avahi-daemon.conf` and change:

```
[reflector]
enable-reflector=yes
```

If you want to limit the reflecting interfaces also edit:

```
[server]
deny-interfaces=eth2
```

### SSL Certificates - without a CA

I didn't want to trust a whole CA - it could sign certificates for the whole
internet on all of my devices and I'm just doing my hobby. I'm not setting
up a private CA witha security key 'n shit. Lets create a wildcard self-signed
certificate which we will trust on the devices and sign client certificates
with it as well. It's good enough and if someone gains root and compromises
the certificate key - they already have access to all of the confidential
data we're gonna transfer...

Create default certificate:

```bash
openssl req -new -x509 -nodes -newkey rsa:2048 -keyout /data/certs/default.key -out /data/certs/default.crt -subj "/C=GR/ST=Attiki/L=Athens/O=HomeCert/CN=*.server.lan"
```

Create a client certificate

```bash
openssl req -new -key /tmp/client/client.key -out /tmp/client/client.req -subj "/C=GR/ST=Attiki/L=Athens/O=HomeCert"
openssl x509 -req -in /tmp/client/client.req -CA default.crt -CAkey default.key -set_serial 1000 -extensions client -days 365 -outform PEM -out /tmp/client/client.crt
openssl pkcs12 -export -inkey /tmp/client/client.key -in /tmp/client/client.crt -out /tmp/client/client.p12
```

Fix Jira certificate issues:

```bash
docker exec -it jira_jira_1 keytool -import -trustcacerts -keystore /var/atlassian/application-data/jira/cacerts -storepass changeit -alias Proxy -import -file /proxy.crt
```
