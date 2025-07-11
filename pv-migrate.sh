#!/usr/bin/env bash
set -euo pipefail

yq --version || { echo "yq command not found. Please install yq-go to proceed."; exit 1; }
pv-migrate --version || { echo "pv-migrate command not found. Please install pv-migrate to proceed."; exit 1; }

yq --version | grep mikefarah || { echo "yq version is not compatible. Please install yq-go version 4.x, not yq"; exit 1; }

namespace=$1
pvc_name=$2

if [ -z "$namespace" ] || [ -z "$pvc_name" ]; then
  echo "Usage: $0 <namespace> <pvc_name>"
  exit 1
fi

# Get the storageClass of the PVC
storage_class=$(kubectl get pvc "$pvc_name" -n "$namespace" -o jsonpath='{.spec.storageClassName}')

# Check if the storageClass matches openebs-* wildcard
if grep -q '^openebs-.*' <<< "$storage_class"; then
	echo "The storage class matches 'openebs-*'. No migration needed."
fi

echo "PVC: $pvc_name Namespace: $namespace"
echo "The storage class '$storage_class' does not match the 'openebs-*' wildcard. Continue (only 'yes' will be accepted)?"
read -r answer

if [ "$answer" != "yes" ]; then
	echo "Bye"
	exit 0
fi

echo
echo

# Get the PV name associated with the PVC
pv_name=$(kubectl get pvc "$pvc_name" -n "$namespace" -o jsonpath='{.spec.volumeName}')
echo "PV of the PVC: $pv_name"

# Download the PVC YAML
backup_dir=/tmp/pv-migrate-fish
mkdir -p $backup_dir
echo "Backing up PVC definition to $backup_dir/$pvc_name.yaml"
kubectl get pvc "$pvc_name" -n "$namespace" -o yaml > "$backup_dir/$pvc_name.yaml"

# Patch the PV to set reclaim policy to Retain
policy=$(kubectl get pv "$pv_name" -o jsonpath='{.spec.persistentVolumeReclaimPolicy}')

if [ "$policy" != "Retain" ]; then
	echo "Patching the PV to get retained when unbound"
	kubectl patch pv "$pv_name" -p '{"spec": {"persistentVolumeReclaimPolicy": "Retain"}}'
else
	echo "PV already has 'Retain' as reclaim policy"
fi

# Change the storageClass in the YAML
echo "Writing the new PVC to $backup_dir/$pvc_name.new.yaml"
yq -o yaml '
  .spec.storageClassName = "openebs-replicated" |
  del(.metadata.finalizers) |
  del(.metadata.creationTimestamp) |
  del(.metadata.resourceVersion) |
  del(.metadata.uid) |
  del(.metadata.annotations) |
  del(.spec.volumeMode) |
  del(.spec.volumeName) |
  del(.status)
' "$backup_dir/$pvc_name.yaml" > "$backup_dir/$pvc_name.new.yaml"

echo "Writing the old renamed PVC to $backup_dir/$pvc_name.old.yaml"
yq -o yaml '
  del(.metadata.finalizers) |
  del(.metadata.creationTimestamp) |
  del(.metadata.resourceVersion) |
  del(.metadata.uid) |
  del(.metadata.annotations) |
  del(.status)
' "$backup_dir/$pvc_name.yaml" > "$backup_dir/$pvc_name.old.yaml"

echo "Renaming the old pvc to $pvc_name-old"
yq -o yaml -i ".metadata.name = \"$pvc_name-old\"" "$backup_dir/$pvc_name.old.yaml"

echo "Deleting the old PVC $pvc_name"
kubectl delete pvc "$pvc_name" -n "$namespace"

echo "Applying the new PVC $pvc_name"
kubectl apply -f "$backup_dir/$pvc_name.new.yaml"

echo "Applying the old renamed PVC $pvc_name-old"
kubectl apply -f "$backup_dir/$pvc_name.old.yaml"

sleep 2

echo "Removing deleted PVC from the old PV"
kubectl patch pv "$pv_name" --type=json -p '[{"op": "remove", "path": "/spec/claimRef"}]'

sleep 2

echo "Migrating the data between the PVCs with pv-migrate"
set +x
pv-migrate --strategies mnt2 --source-namespace "$namespace" --dest-namespace "$namespace" --source "$pvc_name-old" --dest "$pvc_name" --helm-set rsync.nodeSelector.provider=oracle
