# Incident: Longhorn v2 stuck detach + cross-node reactor churn (2026-06-23/24)

## TL;DR
A single v2 volume (`pvc-0c1b563f`, hextoaster) wedged in `detaching`. Restarting
gr0's instance-manager (IM) — the reflex from the prior incident — **did not fix it and
made things worse**, because we kept restarting **into the same trap**: a stale
attachment ticket + the SPDK leftover-controller bug. Each gr0 IM restart also **changed
gr0's pod IP**, leaving stale NVMe-oF peer addresses that **wedged replicas on OTHER nodes**
(fra1) via endless keep-alive retries, which starved that node's single SPDK reactor and
slowed all attach/detach there.

Root causes (three distinct, all v2/SPDK):
1. **Stale `longhorn-ui` attachment ticket** pinned the volume attached on gr0; with the
   workload at 0 replicas there was nothing legitimately holding it, but the ticket kept
   the engine from going down.
2. **SPDK leftover-controller wedge (upstream #10293):** `nvmf_subsystem_get_listeners`
   RPC hangs for the full 60s on a broken subsystem, so engine/replica **delete never
   completes** → volume frozen in `detaching`.
3. **Cross-node keep-alive storm:** wedged replicas held NVMe-oF connections to a **dead
   gr0 IP from a previous restart**; SPDK retried keep-alives every ~2s forever on the
   one reactor thread, starving attach/detach on the *other* node.

**Red herrings we burned hours on:** "gr0 reactor at 80-90% CPU = saturated" (FALSE — SPDK
reactors busy-poll `while(1)`, 100% is by design, ref spdk #285); and "volume pinned to
IM image v1.11.0 = upgrade failed" (FALSE — see "v1.11.0 image is cosmetic" below).

## Environment
- Same cluster as `INCIDENT-2026-06-22-v2-orphan-teardown.md` (read that first).
- Longhorn `v1.12.0`, manager + all 4 IM pods on `v1.12.0`, only `v1.12.0` EngineImage
  deployed. Cross-version skew from the prior incident is RESOLVED.
- Nodes: fra0, fra1, gr0 (cp+etcd+storage), srv0 (worker+storage). Inter-node connectivity
  still flaky. `replica-auto-balance` still ON; `offline-replica-rebuilding` global = `true`.
- Affected vol: `pvc-0c1b563f` (hextoaster-data-hextoaster-0, 512Mi, v2, 3 replicas).
- Collateral faulted vols: `pvc-442ee1f4` (victorialogs), `pvc-d1a05a82` (plane-redis).

## Symptoms
- `pvc-0c1b563f` stuck `state=detaching`, `robustness=unknown`; engine `desireState=stopped`
  but `currentState=running`; resourceVersion FROZEN (not even reconciling).
- IM log loop every ~30-60s:
  `Failed to delete engine ... nvmf_subsystem_get_listeners ... timeout 1m0s`.
- After clearing it, fra1 began slowing all attach/detach. fra1 IM log: ~88 lines/2min of
  `nvme_ctrlr_keep_alive: *ERROR* [... ,10.200.3.75,1] Submitting Keep Alive failed` +
  `Disconnecting host ... due to keep alive timeout`. `10.200.3.75` = a DEAD old gr0 IM IP.

## Root cause (mechanism, step by step)
1. `pvc-0c1b563f` was left with a **`longhorn-ui` attachment ticket** (type `longhorn-api`,
   node gr0) — a leftover from a manual UI Attach/Salvage click. Workload (hextoaster) was
   scaled to 0, pod gone. So nothing legit wanted it, but the ticket kept desired-attached.
2. The engine teardown calls `nvmf_subsystem_get_listeners` on the engine's volume NQN.
   On the wedged subsystem this RPC **hangs 60s and times out** (upstream #10293 — leftover
   replica/controller not cleaned up). Delete never finishes → `detaching` forever.
3. **Why every restart failed (the ordering bug):** restarting gr0's IM with the ticket
   still present → fresh spdk_tgt comes up → AD controller immediately re-honors the ticket
   → re-attaches `0c1b563f` → re-hits #10293 → re-wedges. Infinite loop. We were restarting
   INTO the trap.
4. **Why other nodes got slow:** each gr0 IM restart gave gr0 a **new pod IP**
   (.119 → .220 → .156 …). Replicas/engines that had cached the OLD gr0 IP as an NVMe-oF
   peer kept trying to keep those connections alive. On fra1 the two faulted volumes'
   replica subsystems (`r-d43da69b`, `r-78543d4b`) spun on failed keep-alives to dead
   `10.200.3.75` every ~2s. v2 runs **one SPDK reactor thread per node**, and that same
   thread serves all attach/detach RPCs → fra1 crawled. (Same single-reactor starvation as
   the prior incident, but the trigger was dead-peer keep-alive, not orphan lvol count.
   fra1 was otherwise CLEAN: 56 bdevs, 3 orphans — NOT a gr0-style orphan pileup.)
5. The two collateral volumes faulted earlier during a gr0 restart (their only-or-best copy
   was mid-flight), then their fra1 replicas wedged the same way (#10293), keeping them
   `detaching/faulted` AND generating the keep-alive storm.

### Matching upstream issues
- #10293 `v2 engine stuck in detaching-attaching loop if previous replica not cleaned up`
  (milestone v1.9.0; workaround: "manually detach the leftover replica nvme controller").
- #9919 `v2 volume stuck in detaching/attaching loop forever if replica crash`.
- #10112 `v2 volume could get stuck in Detaching/Faulted after nodes reboot`.
- #10167 `Engine v2 I/O blocked 1-2 min after IM pod deletion` — IM restarts on a new IP,
  errno=110 (connection timeout), I/O recovery delayed. Directly explains the IP churn pain.
- spdk #285 — reactor 100% CPU is **by design** (`while(1)` poll loop). CPU% is NOT a
  saturation signal.

## v1.11.0 image on the volume is COSMETIC, not a failed upgrade
- `volume.status.currentImage` / `spec.image` showed `v1.11.0` even after recovery.
- BUT the engine/replicas run **inside the v1.12.0 IM pod** (verified: engine's
  `instanceManagerName` → that pod's container image is `v1.12.0`). The running bits ARE
  v1.12.0; only the CR label is stale.
- **v2 does NOT support live engine-image upgrade** (Longhorn 1.12.0 docs, V2 Data Engine
  → System Upgrade: "V2 volumes do not support live upgrades ... must be detached before
  upgrading. Support planned for 1.12 → 1.13"). The per-volume "Upgrade Engine" button is
  **intentionally greyed out** for v2 (#7445). Longhorn **rejects** `volume.spec.image`
  edits for v2 (#7446). UI also wrongly shows "upgrade available" for v2 (#7489).
- v2 has no per-volume engine image; all v2 vols share the per-node IM (SPDK process). A v2
  volume adopts the new version simply by **detach → reattach** (it joins the current
  v1.12.0 IM). The label just isn't rewritten. **Nothing to fix; do NOT patch spec.image.**

## What actually worked (the fix)
**Order matters: clear the K8s-side pin FIRST, then restart the IM.**
1. **Cleared the stale `longhorn-ui` ticket.** Tried Longhorn API detach
   (`POST /v1/volumes/<v>?action=detach` via `longhorn-frontend` svc) — **no-op** while the
   teardown RPC was hung. Fell back to removing just the ticket key from the
   VolumeAttachment CR (surgical; the AD controller owns this object, not Volume/Engine/
   Replica spec):
   ```
   kubectl -n longhorn-system patch volumeattachments.longhorn.io <vol> --type=json \
     -p='[{"op":"remove","path":"/spec/attachmentTickets/longhorn-ui"}]'
   ```
2. **THEN restarted gr0 IM.** With no ticket, the fresh target did NOT re-attach `0c1b563f`
   → wedged subsystem not recreated → engine `desireState=stopped` satisfied → volume
   detached. (`offline-replica-rebuilding=true` then briefly auto-attached it to rebuild
   the 3rd replica; it flapped attaching↔detaching a few cycles then settled `detached`,
   then `attached/healthy` once hextoaster scaled to 1 — picking up v1.12.0 runtime.)
3. **fra1 slowness:** the two faulted vols' fra1 replicas were wedged (#10293,
   `get_listeners` 60s timeout) and `controller-detach` returned "No such device" (stale
   conn was subsystem-side, not a detachable host controller) → **no surgical option** →
   **fra1 IM restart** (data pre-verified safe: 442ee1f4 copy on srv0, d1a05a82 copy on
   gr0, both lvols present on disk). Fresh spdk_tgt dropped the wedged replicas → both vols
   went `detaching/faulted` → `detached` cleanly; keep-alive storm → **0 lines**; reactor
   freed; cluster converged (rebuilds drained).

## Resolution (as of 2026-06-24 ~11:52Z)
- `pvc-0c1b563f` recovered, `attached/healthy`, running in v1.12.0 IM.
- `pvc-442ee1f4` + `pvc-d1a05a82` cleanly `detached`, surviving replica intact
  (srv0 / gr0 respectively). Scale their workloads to 1 to bring them back (clean attach,
  v1.12.0). NO data loss.
- fra1 attach/detach responsive; keep-alive storm gone; ~15 vols degraded but actively
  rebuilding (normal post-restart re-import churn, draining).

## DO / DON'T (hard-won)
- **DON'T** restart an IM as the reflex for a stuck `detaching` v2 volume. First check for a
  **stale attachment ticket** (`kubectl -n longhorn-system get volumeattachments.longhorn.io
  <vol> -o yaml`) and clear it. Restarting with the ticket present just re-wedges.
- **DON'T** trust CPU% on the SPDK reactor as a health signal — it's always ~100% by design.
  Use RPC latency + `subsystem-get`/`get_listeners` hang behavior instead.
- **DON'T** read `volume.status.currentImage` as the running version for v2. Check the
  engine's `instanceManagerName` → that pod's container image. Don't patch `spec.image`.
- **DON'T** restart an IM holding the only good copy of a volume without first verifying the
  data lvols exist on another node (`go-spdk-helper lvol get | grep <vol>`).
- **DO** expect gr0 IM restarts to change its pod IP and orphan NVMe-oF peer refs on OTHER
  nodes → keep-alive storms there. After any IM restart, grep neighbor IM logs for
  `keep alive` / dead-IP errors.
- **DO** clear K8s-side pin (ticket) BEFORE restarting the SPDK side. Order is the fix.

## Permanent fixes / follow-ups
- [ ] **Stop the IP-churn amplifier:** investigate pinning IM pod IPs or shortening NVMe-oF
      `transportAckTimeout` / `fast-io-fail-timeout` so dead-peer connections drop fast
      instead of looping keep-alives (ref #10167). Until then, minimize IM restarts.
- [ ] **Drain, don't restart:** to clear a node, move volumes off via controlled
      scale-down/up (clean detach→attach) ONE at a time; reserve IM restarts for true
      in-process wedges (`get_listeners` hang) with data pre-verified elsewhere.
- [ ] Keep `replica-auto-balance` OFF during recovery (churn amplifier on flaky nodes).
- [ ] Reconsider `offline-replica-rebuilding=true`: it auto-attaches detached degraded
      volumes to rebuild, causing attach/detach flapping during recovery windows. Consider
      disabling globally or per-volume (`volume.spec.offlineRebuilding=disabled`) while
      firefighting.
- [ ] **Migrate the 24 v1.11.x-pinned v2 volumes to v1.12.0** the supported way: each adopts
      v1.12.0 on its next detach→reattach (pod restart / node drain / scale 0→1). They can't
      migrate while attached — that's the documented v2 constraint, not breakage. For ANY
      future Longhorn upgrade, **detach all v2 volumes first** (no live upgrade until 1.13).
- [ ] Strongly weigh **selective v2 activation** (keep critical/small volumes on v1) — v2
      attach/detach is repeatedly fragile on this cluster's reboot/connectivity profile.
      Ref: longhorn.io selective-v2-data-engine-activation.
- [ ] Alerting: engine/replica `desireState=stopped` & `currentState=running` >5min;
      IM log `nvmf_subsystem_get_listeners ... timeout`; cross-node `Submitting Keep Alive
      failed` rate; stale attachment tickets on detached/0-replica workloads.

## Useful commands
```sh
# stuck-detach triage: state + tickets + engine
V=pvc-XXXX
kubectl -n longhorn-system get volumes.longhorn.io $V \
  -o jsonpath='state={.status.state}/{.status.robustness}{"\n"}'
kubectl -n longhorn-system get volumeattachments.longhorn.io $V -o yaml | sed -n '/spec:/,$p'
kubectl -n longhorn-system get engines.longhorn.io -l longhornvolume=$V \
  -o custom-columns=NODE:.spec.nodeID,DESIRE:.spec.desireState,CUR:.status.currentState

# clear a stale UI ticket (after API detach no-ops) — surgical, AD-controller-owned object
kubectl -n longhorn-system patch volumeattachments.longhorn.io $V --type=json \
  -p='[{"op":"remove","path":"/spec/attachmentTickets/longhorn-ui"}]'

# confirm the leftover-controller hang (the #10293 signature)
POD=<im-pod>
kubectl -n longhorn-system exec $POD -- timeout 70 go-spdk-helper nvmf listener-get \
  nqn.2023-01.io.longhorn.spdk:volume-$V      # hangs 60s -> wedged

# find cross-node keep-alive storm (dead-peer churn) in a neighbor IM
kubectl -n longhorn-system logs <neighbor-im> --since=2m | grep -iE "keep alive"

# verify which version a v2 volume ACTUALLY runs (NOT status.currentImage)
IM=$(kubectl -n longhorn-system get engines.longhorn.io ${V}-e-0 \
  -o jsonpath='{.status.instanceManagerName}')
kubectl -n longhorn-system get pod $IM -o jsonpath='{.spec.containers[0].image}{"\n"}'

# data-safety check before restarting an IM (are vol lvols on another node?)
kubectl -n longhorn-system exec <other-node-im> -- go-spdk-helper lvol get | grep $V

# IM restart (LAST resort; clear tickets first, verify data elsewhere)
kubectl -n longhorn-system delete pod <im-pod>            # graceful
kubectl -n longhorn-system delete pod <im-pod> --grace-period=0 --force  # only if stuck
```
