# Incident: Longhorn v2 orphan-teardown wedge + cross-version upgrade (2026-06-22/23)

## TL;DR
Sporadic, "random" cluster downtime was caused by **Longhorn v2 (SPDK) data-engine
instance-managers getting wedged on orphaned replica/snapshot lvols that could not be
deleted** (`bdev_lvol_delete -> Device or resource busy`, and stale NVMe-oF namespaces
`still exists after delete`). Because v2 runs **one SPDK process per node**, a single
stuck teardown starves the whole node's storage → every volume touching that node
hangs (`attaching` / `ContainerCreating`).

Root trigger: a **half-finished upgrade** (manager `v1.12.0`, instance-managers split
between `v1.11.2` and `v1.12.0`). Operating v2 volumes across mismatched IM versions
generated orphaned teardowns the old IMs couldn't clean up.

**Not** a disk-space problem (that was a red herring) and **not** a reason to abandon v2.
The matching v2 teardown bugs are already fixed in <=1.10.0 (so present in 1.12.0); the
problem was the version skew + leftover orphans, not a missing patch. NOTE: `1.12.0` is
the newest stable release — there is NO 1.12.x patch to bump to.

## Environment
- Longhorn `v1.12.0` (chart pinned in `chartfile.yaml`), `persistence.dataEngine: 'v2'`
  is the **cluster default** (`envs/longhorn/main.jsonnet`).
- v2 disk is a thin LV `mainpool-longhorn` sharing one thin-pool with root+containerd
  (`nixos/system/disk.nix`) -> Longhorn's reported "max" is fictional vs physical.
- Nodes: fra0, fra1, gr0 (control-plane+etcd+storage), srv0 (worker+storage).
  Connectivity between nodes is not rock-solid (relevant: rebuilds/teardowns happen often).
- `replica-auto-balance` was ENABLED mid-incident and KEPT ON (user needs it for flaky
  connectivity). Caveat: on v2 it increases rebuild churn = more chances to hit the bug.

## Symptoms observed
- `Disk fra0-longhorn ... is not schedulable for more replica ... CurrentAvailable <= 25%`
  (DiskPressure) — the original complaint, but a SECONDARY issue.
- Pods stuck `ContainerCreating`; volumes stuck `attaching`;
  `AttachVolume.Attach failed ... DeadlineExceeded`.
- forgejo-0 down ~18h; woodpecker-server-0 down ~4h.
- Instance-manager logs looping every ~30s:
  - `bdev_lvol_delete ... {"code": -32603,"message": "Device or resource busy"}`
  - `Failed to delete replica with cleanupRequired flag true`
  - `NVMe path '<replica>' still exists after delete`

## Root cause (mechanism)
1. An IM restart (upgrade/reboot/OOM/auto-balance rebuild) kills v2 replica processes;
   Longhorn deletes the failed replica.
2. The SPDK lvol delete fails `Device or resource busy` because a stale exposed bdev
   (`-rebuilding` / `-cloning` NVMe-oF namespace) or a degraded esnap/snapshot blob still
   references it. Longhorn does NOT force-remove (upstream #10474) -> retries forever.
3. One SPDK process per node => the wedged loop starves ALL v2 volumes on that node.
4. Cross-version state (v1.12.0 manager + v1.11.2 IMs) is what kept generating orphaned
   teardowns the old IMs couldn't finish.

### Matching upstream issues (all CLOSED/fixed, present in 1.12.0)
- #10474 `[IMPROVEMENT] Lvol is not force-removed if Blob is busy` (milestone v1.9.0)
- #10107 `v2 stuck degraded, continuously rebuilds/deletes after kubelet restart` (v1.10.0)
- #10335 `v2 fails to cleanup error replica and rebuild` (v1.10.0)
- #10140 `spdk Device or resource busy while registering` (v1.9.0)
- #13267 `v1.12.0 breaks volume silently every day` -> closed as HARDWARE (PSU), NOT a regression.

## Actions taken
1. **gr0 IM restart** (`delete pod instance-manager-1a8457...`). Old pod stuck
   `Terminating` (dead container process, kubelet couldn't finalize) -> force-deleted
   `--grace-period=0 --force`. Fresh IM dropped the orphan lvols + stale NQNs; busy-loop
   cleared; forgejo-0 recovered (Running 1/1). bdev count 82 -> 8.
2. **srv0 IM restart** — same orphan teardown loop (`r-c584d162 still exists after delete`).
   Graceful term worked. New IM came up as **v1.12.0** (advanced the upgrade).
   woodpecker-server-0 + atuin-0 recovered.
3. **fra1 IM restart** — same wedge; upgraded to v1.12.0.
4. **fra0 IM restart** — final node -> all 4 IMs now **v1.12.0** (version skew ELIMINATED).

### Restart procedure that worked (per node, one at a time)
- Pre-check: every volume engine-attached on the node has a healthy RW replica ELSEWHERE.
- Let in-flight rebuilds (WO replicas) finish BEFORE draining the next node.
- `kubectl -n longhorn-system delete pod <instance-manager-pod>`; wait ~40s for graceful
  termination; if stuck `Terminating` with dead process -> `--grace-period=0 --force`.
- Restarting a stopped v1.12.0 IM (or recreating the running one) activates the upgrade.

## Resolution (as of 2026-06-23 ~02:50Z)
- **fra1 second IM restart FIXED the not-ready disk.** Graceful termination completed on
  its own (spdk_tgt stopped cleanly, NO force kill needed); fresh IM re-imported the
  lvstore clean and dropped the 7 orphan esnap blobs. Disk -> `Ready=True/Schedulable=True`,
  health collection fresh again. Orphan/busy loop: 0 errors.
- **All 4 disks now Ready + Schedulable** (fra0 no longer in DiskPressure — auto-balance
  redistributed replicas and freed space).
- **All 24 volumes `attached`.** The 3 previously-faulted volumes (plane-pgdb /
  victoriametrics / headscale) and the 6 stuck-`attaching` volumes all recovered and
  reattached on their own once fra1's disk came back. NO manual salvage was ultimately
  needed; NO data loss.
- Tail state: 18 healthy, 6 degraded and actively rebuilding their 2nd replica
  (22-74%); all attached and serving. Expected to converge to all-healthy.

### Historical fallout (now resolved — kept for context)
- 3 volumes faulted after fra0 restart (only RW replica was on fra0): pvc-1298ec49 (plane),
  pvc-7365930a (victoriametrics 50GiB), pvc-a3f3f895 (headscale). Data was intact on fra0
  lvols throughout; recovered via reattach after fra1 disk returned.
- fra1 disk `Ready=False`/`DiskNotReady`: 7 orphaned degraded esnap/snapshot lvols
  (0a9364cf, 4ec50410, 5f77f7c1, 604b7062, a31d20e7, d71c40f5, ea242e92) referenced missing
  backing bdevs; `bdev_get_bdevs`/DiskGet enumeration hung -> disk-config RPC DeadlineExceeded.
  Cleared by the clean lvstore re-import on second IM restart.
- fra0 DiskPressure (~39Gi, under 25% floor) — cleared by auto-balance redistribution.

## Recovery playbook for the faulted volumes (NO direct CR patching — user preference)
- Option 1 (preferred): **Longhorn UI -> volume -> Salvage**, pick the known-good replica
  (fra0: r-55b5a8e2 / r-ab38eaa6 / r-8c2e7de0). Requires a SCHEDULABLE disk (fix fra1/fra0
  pressure first).
- Option 2: `kubectl scale` workload to 0, let volume fully detach, scale back to 1 ->
  re-runs auto-salvage from a clean attach.
- Salvage needs a schedulable target disk -> must clear fra1 not-ready AND fra0 DiskPressure.

## Permanent fixes / follow-ups
- [DONE] Finish the upgrade so all IMs are one version (was the root trigger).
- [ ] Resolve fra0 DiskPressure for good: give Longhorn a REAL fixed-size LV instead of a
      thin-pool sibling, OR set Longhorn disk `storageReserved` to reflect true physical
      headroom (`disk.nix` + Longhorn disk config). Thin-pool overcommit makes Longhorn's
      accounting lie.
- [ ] Add alerting (Grafana MCP) on: engines `currentState != running` / `starting=true`
      >5 min; instance-manager `Device or resource busy` / `still exists after delete`
      rate; longhorn node disk `Schedulable=False`; disk `healthDataLastCollectedAt` going
      stale.
- [ ] Consider selective v2 activation (keep critical/small volumes on v1) instead of v2
      as the global default, until v2 teardown is battle-tested on this cluster.
      Ref: longhorn.io selective-v2-data-engine-activation.
- [ ] Watch `replica-auto-balance` (kept ON): it increases v2 rebuild churn. Revisit if
      orphan-teardown recurs.
- [ ] Avoid restarting an IM that is the ONLY RW replica holder for a volume without first
      rebuilding a second replica elsewhere (caused the 3 faulted volumes). With v2 + flaky
      nodes, prefer 3 replicas for critical single-copy volumes.

## Useful commands
```sh
# IM versions per node
kubectl -n longhorn-system get pods -l longhorn.io/component=instance-manager \
  -o custom-columns=NODE:.spec.nodeName,IMG:.spec.containers[0].image,PHASE:.status.phase

# disk schedulable/ready + space per node
kubectl -n longhorn-system get nodes.longhorn.io <node> -o yaml | less

# stuck teardown loop in IM logs
kubectl -n longhorn-system logs <im-pod> --since=2m | \
  grep -E "Device or resource busy|still exists after delete"

# inspect SPDK bdevs/lvols on a node IM (NO rpc.py shipped; use go-spdk-helper)
kubectl -n longhorn-system exec <im-pod> -- go-spdk-helper bdev get
kubectl -n longhorn-system exec <im-pod> -- go-spdk-helper lvol get
kubectl -n longhorn-system exec <im-pod> -- go-spdk-helper lvs get

# orphan lvol surgical delete (last resort, only if no owning replica CR)
kubectl -n longhorn-system exec <im-pod> -- \
  go-spdk-helper lvol delete --alias <lvstore>/<lvol-name>

# restart an IM (recovery + advances upgrade); force only if stuck Terminating w/ dead proc
kubectl -n longhorn-system delete pod <im-pod>
kubectl -n longhorn-system delete pod <im-pod> --grace-period=0 --force
```
