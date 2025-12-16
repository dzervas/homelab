#!/usr/bin/env bash
set -euo pipefail

yq --version || { echo "yq command not found. Please install yq-go to proceed."; exit 1; }
pv-migrate --version || { echo "pv-migrate command not found. Please install pv-migrate to proceed."; exit 1; }
jq --version || { echo "jq command not found. Please install jq to proceed."; exit 1; }

yq --version | grep mikefarah || { echo "yq version is not compatible. Please install yq-go version 4.x, not yq"; exit 1; }

namespace=$1
pvc_name=$2
new_storage_class=linstor
old_storage_class=openebs-replicated

if [ -z "$namespace" ] || [ -z "$pvc_name" ]; then
  echo "Usage: $0 <namespace> <pvc_name>"
  exit 1
fi

# Find all Deployments/StatefulSets using a PVC
find_workloads_using_pvc() {
  local ns=$1 pvc=$2

  kubectl get pods -n "$ns" -o json | jq -r --arg pvc "$pvc" '
    .items[] |
    select(.spec.volumes[]? | .persistentVolumeClaim?.claimName == $pvc) |
    .metadata.ownerReferences[]? |
    select(.kind == "ReplicaSet" or .kind == "StatefulSet") |
    "\(.kind)/\(.name)"
  ' | sort -u | while read -r owner; do
    if [[ "$owner" == ReplicaSet/* ]]; then
      rs_name=${owner#ReplicaSet/}
      kubectl get rs "$rs_name" -n "$ns" -o json | jq -r '
        .metadata.ownerReferences[]? |
        select(.kind == "Deployment") |
        "Deployment/\(.name)"
      '
    else
      echo "$owner"
    fi
  done | sort -u
}

# Scale workload to 0 and save original replicas
scale_down_workloads() {
  local ns=$1 backup_file=$2
  shift 2
  echo "[]" > "$backup_file"

  for workload in "$@"; do
    kind=${workload%/*}
    name=${workload#*/}
    replicas=$(kubectl get "$workload" -n "$ns" -o jsonpath='{.spec.replicas}')

    jq --arg k "$kind" --arg n "$name" --argjson r "$replicas" \
      '. += [{"kind": $k, "name": $n, "replicas": $r}]' \
      "$backup_file" > "$backup_file.tmp" && mv "$backup_file.tmp" "$backup_file"

    echo "Scaling down $workload (was $replicas replicas)"
    kubectl scale "$workload" --replicas=0 -n "$ns"
  done
}

# Wait for all pods using PVC to terminate
wait_for_pods_terminated() {
  local ns=$1 pvc=$2
  echo "Waiting for pods using $pvc to terminate..."
  while true; do
    count=$(kubectl get pods -n "$ns" -o json | jq -r --arg pvc "$pvc" '
      [.items[] | select(.spec.volumes[]? | .persistentVolumeClaim?.claimName == $pvc)] | length
    ')
    [ "$count" -eq 0 ] && break
    echo "  $count pod(s) still running..."
    sleep 5
  done
  echo "All pods terminated"
}

# Restore workloads from backup
restore_workloads() {
  local ns=$1 backup_file=$2
  if [ ! -f "$backup_file" ]; then
    echo "No workload backup found"
    return
  fi

  jq -c '.[]' "$backup_file" | while read -r entry; do
    kind=$(echo "$entry" | jq -r '.kind')
    name=$(echo "$entry" | jq -r '.name')
    replicas=$(echo "$entry" | jq -r '.replicas')
    echo "Restoring $kind/$name to $replicas replicas"
    kubectl scale "$kind/$name" --replicas="$replicas" -n "$ns"
  done
}

# Print recovery instructions on failure
print_recovery_instructions() {
  local ns=$1 backup_file=$2
  echo ""
  echo "============================================"
  echo "MIGRATION FAILED - Manual recovery required"
  echo "============================================"
  echo ""
  echo "Workload backup saved to: $backup_file"
  echo ""
  echo "To restore workloads manually:"
  jq -r --arg ns "$ns" '.[] | "  kubectl scale \\(.kind)/\\(.name) --replicas=\\(.replicas) -n \\($ns)"' "$backup_file"
  echo ""
}

# Get the storageClass of the PVC
storage_class=$(kubectl get pvc "$pvc_name" -n "$namespace" -o jsonpath='{.spec.storageClassName}')
if [ "$storage_class" != "$old_storage_class" ]; then
  echo "PVC $pvc_name is not using the old storage class $old_storage_class"
  exit 1
fi

echo "PVC: $pvc_name Namespace: $namespace"
echo "Continue? (only 'yes' will be accepted)"
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

# Prepare backup directory and workload backup file
backup_dir=~/Downloads/pv-migrate-$(date +%Y%m%d%H%M%S)
mkdir -p "$backup_dir"
workload_backup="$backup_dir/workloads.json"

trap 'print_recovery_instructions "$namespace" "$workload_backup"' ERR

# Find and scale down workloads before PVC operations
workloads=$(find_workloads_using_pvc "$namespace" "$pvc_name")
if [ -n "$workloads" ]; then
  echo "Found workloads using this PVC:"
  echo "$workloads" | sed 's/^/  /'
  mapfile -t workloads_arr <<< "$workloads"
  scale_down_workloads "$namespace" "$workload_backup" "${workloads_arr[@]}"
  wait_for_pods_terminated "$namespace" "$pvc_name"
else
  echo "No workloads found using this PVC"
  echo "[]" > "$workload_backup"
fi

# Download the PVC YAML
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
  .spec.storageClassName = "'$new_storage_class'" |
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

sleep 5

echo "Removing deleted PVC from the old PV"
kubectl patch pv "$pv_name" --type=json -p '[{"op": "remove", "path": "/spec/claimRef"}]'

sleep 10

echo "Migrating the data between the PVCs with pv-migrate"
echo "namespace=$namespace pvc_name=$pvc_name"
set +x
pv-migrate --strategies mnt2 --source-namespace "$namespace" --dest-namespace "$namespace" --source "$pvc_name-old" --dest "$pvc_name" --helm-set rsync.nodeSelector.provider=oracle

# Restore workloads after successful migration
echo ""
echo "Migration complete. Restoring workloads..."
restore_workloads "$namespace" "$workload_backup"
echo "Done!"

trap - ERR
