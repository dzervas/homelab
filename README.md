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

## Diff all envs

```bash
tk env list --names | xargs -n1 --verbose tk diff -s
```

## Modem ACME fix

```bash
ln -s /etc/opkg/openwrt/distfeeds.conf /etc/opkg/
opkg update
opkg install acme acme-dnsapi
sed -i 's#/usr/lib/acme/#/usr/local/lib/acme/#' /etc/init.d/acme /usr/local/lib/acme/run-acme
/etc/init.d/acme restart
/etc/init.d/acme enable
opkg install prometheus-node-exporter-lua-openwrt
```

## Deleting snapshot of a non-existing snapshotstorageclass

```bash
k get volumesnapshots -A -o json | jq -r '.items[] | select(.spec.volumeSnapshotClassName == "<volumesnapshotclass>") | "-n " + .metadata.namespace + " volumesnapshot/" + .metadata.name + " volumesnapshotcontents/" + .status.boundVolumeSnapshotContentName' | xargs -L1 kubectl delete
# If the snapshotcontents get stuck due to the finalizer, pass --wait=false to the above command and then run:
k get volumesnapshotcontents -A -o json | jq -r '.items[] | select(.spec.volumeSnapshotClassName == "<volumesnapshotclass>")|.metadata.name'|xargs -n1 kubectl delete volumesnapshotcontents
# On another terminal:
k get volumesnapshotcontents -A -o json | jq -r '.items[] | select(.spec.volumeSnapshotClassName == "<volumesnapshotclass>")|.metadata.name'|xargs -n1 -I% sh -c "kubectl patch volumesnapshotcontents --type json -p '[{\"op\": \"remove\", \"path\": \"/metadata/finalizers\"}]' %; sleep 3"
```

Delete old pv/pvcs:

```bash
k get pvc -A -o json | jq -r '.items[] | select(.spec.storageClassName == "openebs-replicated") | "-n " + .metadata.namespace + " " + .metadata.name' | xargs -L1 kubectl delete pvc
k get pv -o json | jq -r '.items[] | select(.spec.storageClassName == "openebs-replicated")|.metadata.name'|xargs -n1 kubectl patch pv --type json -p '[{"op": "remove", "path": "/metadata/finalizers"}]'
```

## Linstor troubles

First of all:

```bash
k linstor error-reports l
```

### StorageException: Failed to get block size...

If for any reason the block paths are missing (e.g. /dev/mainpool/pvc-...):

```bash
ssh <node> vgscan --mknodes
# Maybe lvscan too for good measure
```

### Checking options/protocol/etc. for a pvc

```bash
k exec ds/linstor-satellite.fra0 -- cat /var/lib/linstor.d/pvc-0769addf-02f2-44b3-a9eb-4ee357c78d87.res
```

## Network troubles

```bash
iperf -s # on 1 machine
iperf -c <machine 1 ip> -t 30 -i 1 # on the other machine

# To flush conntrack:
nix shell nixpkgs#conntrack-tools --command conntrack -F
```
