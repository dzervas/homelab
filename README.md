# HomeLab Kubernetes

To get a client certificate from cert-manager:

```bash
export CLIENT=desktop
kubectl get -n cert-manager secret client-$CLIENT-certificate -o go-template='{{index .data "tls.crt" | base64decode}}' > $CLIENT.pem
kubectl get -n cert-manager secret client-$CLIENT-certificate -o go-template='{{index .data "tls.key" | base64decode}}' >> $CLIENT.pem
openssl pkcs12 -export -out $CLIENT.p12 -in $CLIENT.pem
```

iOS and Windows need P12 of PFX with TripleDES encryption:

```bash
export CLIENT=mobile
kubectl get -n cert-manager secret client-$CLIENT-certificate -o go-template='{{index .data "tls.crt" | base64decode}}' > $CLIENT.pem
kubectl get -n cert-manager secret client-$CLIENT-certificate -o go-template='{{index .data "tls.key" | base64decode}}' >> $CLIENT.pem
openssl pkcs12 -export -out $CLIENT.pfx -in $CLIENT.pem -descert -legacy
```

## Create kube config for service account

```bash
export NAMESPACE=dzervit
export SERVICE_ACCOUNT=dzervit-sa
kubectl --kubeconfig /tmp/newkubeconfig config set-credentials $SERVICE_ACCOUNT --token $(kubectl -n $NAMESPACE create token $SERVICE_ACCOUNT)
kubectl --kubeconfig /tmp/newkubeconfig config set-context default --user $SERVICE_ACCOUNT --namespace $SERVICE_ACCOUNT --cluster default
kubectl --kubeconfig /tmp/newkubeconfig config set-cluster default --server $(kubectl config view -o jsonpath='{$.clusters[?(@.name == "'$(kubectl config current-context)'")].cluster.server}')
kubectl --kubeconfig /tmp/newkubeconfig config set clusters.default.certificate-authority-data $(kubectl config view -o jsonpath='{$.clusters[?(@.name == "'$(kubectl config current-context)'")].cluster.certificate-authority-data}' --raw)
```

## Modem ACME fix

```bash
ln -s /etc/opkg/openwrt/distfeeds.conf /etc/opkg/
opkg update
opkg install acme acme-dnsapi
/etc/init.d/acme restart
/etc/init.d/acme enable
opkg install prometheus-node-exporter-lua-openwrt
```
