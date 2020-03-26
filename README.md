# HomeLab

Deployment of my HomeLab server with OpenStack & various services.
It is assumed that OpenStack is deployed with:

- designate
- magnum
- octavia
- swift
- trove

## OpenStack

Download the openrc for the admin account. Then:
```bash
source ~/openrc
cd terraform
terraform init
terraform apply
```

### Troubleshooting & Setup

Various stuff I found the hard way while settig up openstack-ansible:

#### Helper to connect to LXC container

Add to root's `.bashrc`:

```bash
function openstack-attach {
	if [ $# -eq 0 ]; then
		echo "Usage $0 <container> [-- <command>]"
		exit 1
	fi

	container=$(lxc-ls -fF NAME | grep $1)
	shift
	lxc-attach $container $@
}
```

#### Self-signed SSL domain

Add to `user_variables.yml`:
```yaml
haproxy_ssl_self_signed_subject: "/C=GB/ST=London/L=Bridge/O=HomeCert/CN=server.lan"
```

and execute `openstack-ansible -e "haproxy_ssl_self_signed_regen=true" /etc/openstack-ansible/playbooks/haproxy-install.yml`

#### Nova error creating network interfaces (vif something?)

`nova.conf`

```conf
vif_plugging_is_fatal = false
vif_plugging_timeout = 0
```

#### Trove DNS NOTIFY & UPDATE errors

`user_variables.yml`

```yaml
designate_pools_yaml:
  - name: "default"
    description: Default Pool
    attributes: {}
    ns_records:
      - hostname: <main domain>.
        priority: 1
    nameservers:
      - host: <os ip>
        port: 53
    targets:
      - type: bind9
        description: Bind9 Server
        masters:
          - host: 127.0.0.1
            port: 5354
        options:
          host: <dns ip>
          port: 53
          rndc_host: 127.0.0.1
          rndc_port: 953
```

#### Magnum nova authentication or SSL errors

TODO: Fix the url from public to internal?

#### Trove nova authentication or SSL errors

`user_variables.yml`:

```yaml
trove_config_overrides:
  DEFAULT:
    nova_compute_endpoint_type: internalURL
```

#### Add Trove datastores

Initialize them:

```bash
openstack-attach trove
for ds in cassandra couchbase couchdb db2 mariadb mongodb mysql percona postgresql pxc redis vertica; do
	/openstack/venvs/trove-20.0.3.dev1/bin/trove-manage --config-file=/etc/trove/trove.conf datastore_update $ds ""
done
```

DONT DO THIS! UNDER DEV!
Build the images (on the host):

```bash
git clone https://opendev.org/openstack/trove /opt/trove
cd /opt/trove/integration/scripts
for ds in cassandra couchbase couchdb db2 mariadb mongodb mysql percona postgresql pxc redis vertica; do
	./trovestack build-image $ds ubuntu xenial false ubuntu "/tmp/trove-${ds}"
	openstack image create "ubuntu-${ds}-trove" --public --disk-format qcow2 --container-format bare --file "/tmp/trove-${ds}"
done
```

## Docker

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

## Ansible

```bash
cd ansible
ansible-galaxy role install -r requirements.yml
```
