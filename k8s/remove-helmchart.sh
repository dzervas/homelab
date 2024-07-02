#!/bin/bash
RELEASE=$1

kubectl -n kube-system patch helmchart "$RELEASE" -p '{"metadata":{"annotations":{"helmcharts.cattle.io/managed-by": "helm-controllerDUMMY"}}}' --type=merge
kubectl -n kube-system patch helmchart "$RELEASE" -p '{"metadata":{"finalizers":null}}' --type=merge
kubectl -n kube-system delete job helm-install-$RELEASE
kubectl -n kube-system get helmchart "$RELEASE" -o yaml

# read -p "Press enter to continue"

kubectl -n kube-system delete helmchart "$RELEASE"
