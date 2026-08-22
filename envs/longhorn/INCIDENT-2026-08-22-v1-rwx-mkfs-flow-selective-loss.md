# Incident: Longhorn v1 RWX mkfs failure caused by flow-selective inter-node packet loss (2026-08-22)

## TL;DR
A new 128 MiB RWX **v1** volume (`netmaker/netmaker-dns-pvc`,
`pvc-92ddd557-7067-4606-8dfe-71972529bf49`) could never finish `mke2fs`: the CSI layer
looped on the **misleading** message `Waiting for volume share to be available`, but the
real failure was the Longhorn engine on **gr0** losing its **sole active v1 replica on
fra1** with a `R/W Timeout` (16s) mid-format, giving `mke2fs` an `EIO` while writing the
ext4 journal.

Investigation escalated from "Longhorn is flaky" to a **measured, severely asymmetric,
flow-selective packet-loss problem on the gr0 → fra1 network path**:

- 4 MiB writes gr0 → fra1 over the pod path take **35–40 s**; Longhorn's replica timeout
  is **16 s** → the sole backend is marked `ERR` → `no backend available` → `EIO`.
- The loss reproduces on the **public underlay without WireGuard** (temporary NodePorts),
  and changes when **only the UDP source port** changes — everything else fixed.
- Packet captures show ~3.5% of encrypted packets counted as transmitted on gr0's `eth0`
  **never arrive on fra1's wire**.

**Proven facts:** loss happens before the receiver capture point; loss is
source-port-dependent; MTU, the replica disk, and guest qdisc drops are excluded.
WireGuard-specific DPI is strongly disfavored; guest-visible NIC counters are clean, but
the post-capture vNIC/hypervisor path remains in scope (see exclusions).
**Leading inference (NOT proven):** a bad ECMP/LAG member (or equivalent flow-hashed
element) in the GRNET ↔ DE-CIX ↔ Oracle transit. Alternative host/middlebox causes and
how to discriminate them are in "If the provider is not at fault" below.

This is the same "connectivity between nodes is not rock-solid" caveat noted in the two
v2 incidents — now quantified. **Do not attach a v1 volume whose only active replica is
across this WAN path.**

## Environment
- Same cluster as `INCIDENT-2026-06-22-v2-orphan-teardown.md` /
  `INCIDENT-2026-06-23-v2-stuck-detach-reactor-churn.md`.
- Nodes: gr0/gr1 (GRNET, Greece), fra0/fra1 (Oracle Frankfurt), srv0.
  Inter-node traffic: TCP → Cilium VXLAN (MTU 1280) → WireGuard `wg0` (MTU 1420) →
  public internet (`eth0` MTU 1500).
- Affected vol: `netmaker/netmaker-dns-pvc` =
  `pvc-92ddd557-7067-4606-8dfe-71972529bf49`, 128 MiB, RWX, **v1 engine**, 2 replicas
  requested. Freshly provisioned as a `pv-migrate` destination (empty, no data at risk).
- gr0 had previously reported `LocalReplicaSchedulingFailure: disks are unavailable`,
  but during this incident Longhorn did create a replacement local v1 replica there. It
  was not yet admitted as an RW engine backend when `mke2fs` started, so the engine was
  still 100% dependent on the sole active fra1 replica at the failure point.
- Collateral with the same signature: Woodpecker CI scratch PVCs (`longhorn-throwaway`,
  1 replica) failing `mkfs.ext4: Input/output error` when the pod landed on gr0 with the
  sole replica on srv0; earlier the same volume's engine on gr0 timed out **both** fra1
  and srv0 replicas before NFS-Ganesha could start.

## Symptoms / timeline
1. Workload/migration pod on gr0 loops:
   ```
   Warning FailedAttachVolume: AttachVolume.Attach failed for volume
   "pvc-92ddd557-7067-4606-8dfe-71972529bf49" ... attachmentID csi-98b2cd07...:
   Waiting for volume share to be available (x6)
   ```
   → looks like an attach/NFS problem. **It is not.** Attach succeeds far enough to expose
   `/dev/longhorn/pvc-92ddd557...` inside the share-manager on gr0.
2. Share-manager sees the volume unformatted and runs `mke2fs`. Initial metadata writes
   succeed; while creating the journal:
   ```
   Creating journal (4096 blocks):
   mkfs.ext4: Input/output error
   ```
3. Engine log at the same moment (sole active replica = fra1):
   ```
   R/W Timeout. No response received in 16s
   Setting replica tcp://10.200.1.35:11671 to ERR
   I/O error: no backend available
   ```
4. NFS-Ganesha never starts (`ganesha.pid: No such file or directory`), so CSI only ever
   reports the downstream `Waiting for volume share to be available`. Longhorn
   auto-salvages, re-attaches, re-formats, re-times-out — indefinitely. The retrying
   `pv-migrate` Job amplified the attach/detach churn.

## Root cause chain (facts)
```
mke2fs 4 MiB journal write on gr0
  → v1 engine (gr0) → TCP → sole replica (fra1)
  → gr0→fra1 path delivers ~0.8–1.25 Mbit/s with ~3–5% flow-selective loss
  → 4 MiB takes 35–40 s (measured)
  → Longhorn engine-replica timeout = 16 s
  → replica ERR → no backend available → EIO → share never comes up
```
The volume can **never** format across this path with a 16 s deadline. Even the max
`engine-replica-timeout` (30 s) is insufficient against a measured 35–40 s transfer.

## Network evidence (measured facts)

### Pod path (TCP over Cilium VXLAN over WireGuard)
- An early bulk iperf run reported 373 Mbit/s with **1,542 retransmits in 10 s**. This
  conflicts with later repeatable short-transfer and raw-path results; treat it as an
  anomalous/transient sample, not evidence that the path was healthy.
- Repeatable 4 MiB single-stream transfers gr0 → fra1: **40.0 s / 145 retx** and
  **35.0 s / 130 retx**. These model the synchronous journal write that actually failed.

### Raw WireGuard (host-network, bound to `wg0` addresses)
```
gr0 → fra1:   1.25 Mbit/s,  35 retransmits
fra1 → gr0: 348.61 Mbit/s,   0 retransmits
```

### Public underlay, NO WireGuard (ephemeral NodePorts on public IPs)
```
gr0 → fra1:   0.83 Mbit/s,  25 retx     fra1 → gr0: 236.5 Mbit/s, 0 retx
gr1 → fra1:  398   Mbit/s, 677 retx     fra1 → gr1:   2.7 Mbit/s, 17 retx
```
→ **WireGuard framing is not required to reproduce the fault.** The NodePort test still
uses Cilium's local service datapath at the destination, but bypasses WireGuard and the
inter-node VXLAN tunnel. Note gr1 shows the mirror-image
directional failure (fra1 → gr1 collapsed), i.e. per-flow, per-direction.

### UDP loss + source-port dependence (the sharpest signature)
- UDP inside WireGuard gr0 → fra1: **4–5.5% loss at only 1 Mbit/s**; reverse 0%.
  (Loss at 1 Mbit/s ≈ rules out congestion.)
- Same src/dst IPs, same rate, same packet size, **only UDP source port varied**:
  ```
  sport 40001: 0%     sport 40002: ~3%    sport 40003: 0%
  sport 40004: 0%     sport 51820 (real WG flow): lossy
  ```
- 40003 is clean toward fra1 but loses **~3.8% toward fra0** → a single-port workaround
  can trade one broken peer path for another (one WG interface = one source port for ALL
  peers).

### Packet-level proof loss is before the receiver
Simultaneous captures during a lossy run:
```
gr0 eth0 transmitted: 1002 encrypted packets
fra1 eth0 received:    967
```
~3.5% vanished between gr0's capture point and fra1's wire. (Caveat: tcpdump taps before
the NIC/driver on egress — see host-side hypotheses below.)

### Route evidence
```
gr0 (83.212.173.226) → GRNET → 83.97.89.66 → DE-CIX 80.81.192.173
  → Oracle 140.91.x.x → fra1 (130.162.36.16)
```
Reverse path differs (Oracle/Colt/GRNET) — consistent with the directional asymmetry.

## Exclusions (all measured)
- **MTU black hole:** eth0 1500 / wg0 1420 / VXLAN+pods 1280 are consistent; DF pings
  pass through 1380-byte payloads inside WG; forcing MSS down to 1200 did NOT help.
- **WireGuard itself:** handshakes current; loss persists under continuous traffic (no
  NAT-expiry pattern); public-IP non-WG TCP reproduces the collapse exactly.
- **Cilium inter-node tunneling:** raw wg0 reproduces the fault without the pod/VXLAN
  path. Public NodePort TCP reproduces it without WireGuard or inter-node VXLAN, though
  Cilium's local NodePort datapath remains involved at the destination.
- **fra1 disk:** 4 MiB fsync completes in **44 ms** locally.
- **Host qdiscs:** zero drops both ends. **Guest-visible NIC state:** zero meaningful
  errors/drops; gr0, gr1, and fra1 each expose a single combined `virtio_net` queue, so a
  guest RSS/XPS choice between good and bad queues is strongly disfavored. Loss after the
  sender capture point in a hypervisor vSwitch/vhost path is NOT excluded.
- **Local GRNET segment:** gr0 ↔ gr1 sustains 850–975 Mbit/s.
- **Congestion:** ~4% loss persists at 1 Mbit/s offered load.
- **ICMP is clean both ways on public IPs** — worthless as a monitor here: ICMP hashes
  differently from a fixed UDP 5-tuple, so per-flow loss is invisible to ping.

## Relationship to prior incidents
- The v2 incidents (2026-06-22/23) blamed teardown bugs but noted "connectivity between
  nodes is not rock-solid" as an amplifier. This incident **quantifies** that: the WAN
  path itself intermittently destroys specific flows. Expect it to have contributed to
  past v1 `R/W Timeout` / auto-salvage churn, RWX share-manager restarts, and replica
  rebuild `EOF` failures. It may also have amplified application-level I/O incidents,
  but those require per-volume correlation before attribution.
- Unlike the v2 incidents, **no instance-manager is wedged here** — restarting IMs does
  nothing for this failure class and risks the churn documented in the 06-23 report.

## Recovery / mitigation
### Immediate (this PVC)
The volume is a brand-new empty migration target — nothing to salvage.
1. Stop the retrying `pv-migrate` Job; let the volume fully detach.
2. Recreate the empty target with **replica count 1** and place engine + replica on the
   SAME node (prefer fra1, or verify that gr0's local v1 replica is RW before formatting).
3. Let mkfs + migration complete locally, THEN raise to 2 replicas and let the rebuild
   trickle across the WAN (rebuilds retry; synchronous mkfs does not).

### Placement policy until the path is fixed
- **Never** attach a v1 volume on gr0 whose only active replica is on fra1 (or generally:
  engine and sole replica must not straddle the gr0↔fra WAN).
- Prefer engine-local replicas (`data locality: best-effort` only helps once gr0 gets a
  v1 disk — provisioning one is still an open follow-up).
- `engine-replica-timeout` can be raised (max 30 s) to reduce sensitivity, but is
  mathematically insufficient vs the measured 35–40 s / 4 MiB — placement is the fix.

### Provider ticket (evidence pack)
Filed against GRNET (and/or Oracle) with:
- src 83.212.173.226 → dst 130.162.36.16
- Sustained 3–5.5% flow-selective UDP loss, present at 1 Mbit/s offered load
- Public TCP: ~0.8 Mbit/s forward vs 236 Mbit/s reverse (no VPN involved)
- Loss toggles with UDP **source port only** (40001 clean / 40002 lossy / 51820 lossy)
- ICMP clean (so their ping-based monitoring will show green)
- pcap delta: 1002 tx @ gr0 vs 967 rx @ fra1
- Forward route via 83.97.89.66 → DE-CIX 80.81.192.173 → Oracle 140.91.x.x
- Stated suspicion: faulty ECMP/LAG member toward DE-CIX/Oracle (**inference, not proof**)

## If the provider is not at fault — alternative causes + discriminating tests
The proven facts constrain any alternative: it must (a) act **before fra1's wire**,
(b) be **flow-hash-selective** (5-tuple), (c) be **direction-specific**, and (d) affect
**both WG UDP and plain TCP**. Candidates, ranked by fit:

1. **Post-capture guest/hypervisor TX path on gr0.** tcpdump taps BEFORE the final
   driver/vhost/vSwitch transmit path, so malformed or dropped packets can appear in the
   sender capture but never reach the receiver. Guest-side RSS/XPS queue selection is now
   strongly disfavored because gr0, gr1, and fra1 expose only one combined `virtio_net`
   queue. Hypervisor-side queues and flow tables remain possible. *Test:* provider-side
   tap captures and vhost/vSwitch counters; in a maintenance window only, toggle GSO/TSO/
   UDP segmentation offloads and retest identical flows.
2. **Hypervisor/virtual-switch on gr0 (GRNET VM) or Oracle VCN ingress on fra1.** Cloud
   vswitches (OVS megaflows, anti-spoof filters, per-flow policers, stateful security
   lists) hash on 5-tuple → flow-selective by construction, and sit after gr0's tcpdump /
   before fra1's. Technically "provider", but NOT the ISP transit. *Test:* second VM on
   the same GRNET hypervisor/subnet reproducing the same per-port loss pattern toward
   fra1; check Oracle VCN flow logs / security-list drop counters for the lossy 5-tuple.
3. **conntrack exhaustion / insert races (either end).** nf_conntrack drops are per-flow.
   Receiver-side is largely excluded for the captured sample (loss was before fra1's
   wire), but sender-side NAT/conntrack on gr0 applies pre-capture… which the capture
   already passed — so only relevant for OTHER samples. *Test:* `conntrack -S | grep -E
   "drop|insert_failed"` and `nf_conntrack_count` vs max on both nodes during a lossy run.
4. **IRQ/CPU steering (RPS/RSS) to a starved CPU.** Flow-hash-selective, but produces
   RX drops on the RECEIVER after the wire — contradicts the pcap delta for gr0→fra1.
   Keep as candidate only for the fra1→gr1 direction. *Test:* `/proc/net/softnet_stat`
   column 2 (drops) deltas per CPU during a lossy run.
5. **Crypto/CPU on WireGuard:** excluded — plain public TCP without WG reproduces the
   collapse; ChaCha20-Poly1305 throughput on these CPUs is orders of magnitude above
   1 Mbit/s.
6. **Host firewall:** static rules are not flow-hash-selective; no drop counters
   incremented; public NodePort test traffic was explicitly allowed. Excluded.

### DPI / WireGuard throttling hypothesis (assessed, currently disfavored)
WireGuard is **trivially identifiable by DPI — by design**. Primary sources:
- The official Known Limitations page has a dedicated "Deep Packet Inspection" section:
  "WireGuard does not focus on obfuscation. Obfuscation, rather, should happen at a layer
  above WireGuard" — https://www.wireguard.com/known-limitations/
- The wire format is a fixed cleartext fingerprint: first byte `message_type` ∈ {1,2,3,4}
  followed by `reserved_zero[3] = {0,0,0}`, with fixed-size handshake messages —
  https://www.wireguard.com/protocol/
- The same page notes TCP-mode/obfuscation wrappers (udptunnel, udp2raw) are the
  sanctioned way to hide it — https://www.wireguard.com/known-limitations/

So an on-path DPI box throttling/degrading identified WG flows is *technically* easy.
**Why the evidence disfavors DPI here (facts):**
- Plain public **TCP** (NodePort iperf, no WG framing) collapses identically → the fault
  is not selecting on WG's signature.
- Random UDP probes to port 51820 toggled between clean and lossy when only the source
  port changed. That strongly supports flow-hash selection, but it was not a controlled
  same-5-tuple comparison of random payload versus valid WireGuard framing.
- Loss is bidirectionally asymmetric per node pair (gr0→fra1 bad, fra1→gr0 clean;
  fra1→gr1 bad, gr1→fra1 mostly fine) — DPI policy would more plausibly be symmetric
  per protocol.
**Discriminating tests if DPI is still suspected:**
- Same 5-tuple, two payloads: real WG handshake initiations vs random UDP of identical
  size/rate. DPI → only the WG-shaped flow suffers; flow-hash fault → both suffer.
- Wrap WG in udp2raw/TCP-obfuscation on the SAME lossy source port. DPI → fixed;
  flow-hash fault → still lossy.
- Move WG's listen port: DPI on port 51820 → fixed; payload-DPI or flow-hash → follows
  behavior of the new 5-tuple, not the port meaning.

## Monitoring / alerting follow-ups
- [ ] Per-peer WAN probes that use the **actual WG 5-tuple** (or at least fixed UDP
      ports), NOT ICMP ping — ICMP was clean throughout this incident.
- [ ] Alert on Longhorn engine `R/W Timeout` / `Setting replica ... to ERR` rate and on
      share-manager restart loops (`ganesha.pid` missing).
- [ ] Alert on any v1 volume attached with a SINGLE active replica that is remote to the
      engine node.
- [ ] Track TCP retransmit rate between node pairs (e.g. periodic short iperf, or
      `nstat TcpRetransSegs` deltas on wg0-bound flows).
- [ ] Re-test the path after the provider ticket; keep the source-port scan handy.

## Useful commands / playbook
```sh
# 1. See the REAL failure behind "Waiting for volume share to be available":
kubectl -n longhorn-system logs -l longhorn.io/share-manager=<vol> --tail=100   # mkfs/ganesha
kubectl -n longhorn-system logs <engine-im-pod> --since=5m | \
  grep -E "R/W Timeout|to ERR|no backend available"

# 2. Where are engine vs replicas? (the straddle check)
V=pvc-XXXX
kubectl -n longhorn-system get engines.longhorn.io -l longhornvolume=$V \
  -o custom-columns=NODE:.spec.nodeID,STATE:.status.currentState,IM:.status.instanceManagerName
kubectl -n longhorn-system get replicas.longhorn.io -l longhornvolume=$V \
  -o custom-columns=NODE:.spec.nodeID,STATE:.status.currentState,MODE:.spec.desireState

# 3. Raw WireGuard path test (host-network pods bound to wg0 IPs), both directions:
iperf3 -s -B <wg0-ip>                        # on peer
iperf3 -c <peer-wg0-ip> -B <local-wg0-ip> -t 10   # watch Retr column

# 4. Source-port loss scan (the discriminator; run at LOW rate, e.g. 1M):
for p in 40001 40002 40003 40004; do
  iperf3 -u -b 1M -t 10 --cport $p -c <peer-ip>; done   # compare Lost/Total per port

# 5. Prove loss is before the receiver (run simultaneously):
tcpdump -ni eth0 -c 100000 'udp port 51820 and host <peer-public-ip>'   # both ends, diff counts

# 6. Small-write reality check on the pod path (what Longhorn actually feels):
dd if=/dev/zero bs=4M count=1 | timeout 60 nc <peer-pod-ip> <port>       # time it vs 16s

# 7. Public-underlay test WITHOUT WireGuard (temporary NodePort, remove after):
kubectl expose pod <iperf-server-pod> --type=NodePort --port=5201 -n <ns>
iperf3 -c <peer-PUBLIC-ip> -p <nodeport> -t 10
kubectl -n <ns> delete svc <svc>                                          # cleanup!
```
