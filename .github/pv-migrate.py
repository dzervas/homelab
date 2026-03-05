#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.13"
# dependencies = [
#     "kr8s>=0.20.15",
# ]
# ///

import kr8s
import sys
from datetime import datetime
from pathlib import Path
from os import getenv

NAMESPACE = None
PVC_NAME = None
NEW_STORAGE_CLASS = getenv("NEW_STORAGE_CLASS", "linstor-ha")
OLD_STORAGE_CLASS = getenv("NEW_STORAGE_CLASS", "linstor")
BACKUP_DIR = Path(f"~/Downloads/pv-migrate-{datetime.now().isoformat(timespec='seconds')}").expanduser()


def findPodsWithPVC():
	for pod in kr8s.get("pods", namespace=NAMESPACE):
		for v in pod.spec.volumes or []:
			if hasattr(v, "persistentVolumeClaim") and v.persistentVolumeClaim.claimName == PVC_NAME:
				print(f"Found pod {pod.metadata.name} using PVC {PVC_NAME}")
				yield pod

def findWorkloadsWithPVC():
	for pod in findPodsWithPVC():
		for owner in pod.metadata.ownerReferences or []:
			if owner.kind in ("ReplicaSet", "StatefulSet", "DaemonSet"):
				yield (owner.kind, owner.name)

def scaleWorkload(kind, name, replicas, backup=True):
	print(f"Scaling {kind} {name} to {replicas} replicas")

	for workload in kr8s.get(kind, name, namespace=NAMESPACE):
		if backup:
			backup_path = BACKUP_DIR / f"{kind.lower()}-{name}-backup.yaml"
			backup_path.write_text(workload.to_yaml())

		workload.scale(replicas)
		break

def main():
	global NAMESPACE, PVC_NAME

	BACKUP_DIR.mkdir(parents=True, exist_ok=True)

	NAMESPACE = sys.argv[1].strip()
	PVC_NAME = sys.argv[2].strip()

	workloads = set(list(findWorkloadsWithPVC()))
	print(f"Found {len(workloads)} workloads using PVC {PVC_NAME}:")

	for kind, name in workloads:
		print(f"  - {kind} {name}")

	for kind, name in workloads:
		scaleWorkload(kind, name, 0)

	pvc = kr8s.objects.PersistentVolumeClaim.get(PVC_NAME, namespace=NAMESPACE)
	# BACKUP_DIR / f"pvc-{PVC_NAME}-backup.yaml"
	# pvc.to_yaml().write_text(BACKUP_DIR / f"pvc-{PVC_NAME}-backup.yaml")
	# pvc.spec.storageClassName = NEW_STORAGE_CLASS
	# pvc.update()

	for kind, name in workloads:
		scaleWorkload(kind, name, 1, backup=False)

if __name__ == "__main__":
	main()
