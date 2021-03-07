# HomeLab Kubernetes

## Setup

In `/etc/systemd/system/k3s.service` append `--disable traefik`.
Traefik v2 is used with much better features, docs & support.

## Usage

To get elastic user password:

```bash
kubectl get -n elasticsearch secret elasticsearch-es-elastic-user -o go-template={{.data.elastic | base64decode}}
```
