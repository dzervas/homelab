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
