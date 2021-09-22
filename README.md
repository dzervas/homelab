# HomeLab Kubernetes

## Setup

```bash
curl -sfL https://get.k3s.io | sh -
```

In `/etc/systemd/system/k3s.service` append `--disable traefik`.
Traefik v2 is used with much better features, docs & support.

Then:

```bash
systemctl daemon-reload
systemctl restart k3s
```

## Usage

To get elastic user password:

```bash
kubectl get -n elasticsearch secret elasticsearch-es-elastic-user -o go-template='{{.data.elastic | base64decode}}'
```

To transfer elasticsearch indices:

```text
POST _reindex
{
  "source": {
    "remote": {
      "host": "https://myhost/elastic/",
      "username": "admin",
      "password": "<pass>"
    },
    "index": "my_index-*"
  },
  "dest": {
    "index": "my_index"
  },
  "script": {
    "lang": "painless",
    "inline": "ctx._index = 'my_index-' + (ctx._index.substring('my_index-'.length(), ctx._index.length()))"
  }
}
```

To get traefik dashboard:

```bash
kubectl port-forward $(kubectl get pods --selector "app.kubernetes.io/name=traefik" --output=name) 9000:9000
```

Stop elasticsearch
```bash
kubectl scale --replicas=0 statefulset.apps/elasticsearch-es-laz
kubectl scale --replicas=0 deployment.apps/kibana-kb
```

To get a client certificate from cert-manager:

```bash
kubectl get -n cert-manager secret client-desktop-certificate -o go-template='{{index .data "tls.crt" | base64decode}}' > desktop.pem
kubectl get -n cert-manager secret client-desktop-certificate -o go-template='{{index .data "tls.key" | base64decode}}' >> desktop.pem
openssl pkcs12 -export -out desktop.p12 -in desktop.pem
```
