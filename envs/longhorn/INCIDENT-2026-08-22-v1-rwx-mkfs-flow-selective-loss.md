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

> **UPDATE 2026-08-23 — the follow-up section at the end of this file supersedes several
> statements above.** The drop element is now localized *inside GRNET*, four hops from
> gr0, at/behind `62.217.100.62`; gr0's guest, vhost and hypervisor vSwitch are excluded
> by measurement, DPI is excluded by a same-5-tuple payload test, physical bit errors are
> excluded by a packet-size test, and policers/congestion are excluded by a
> rate-independence test. See
> "Follow-up 2026-08-23: same-5-tuple discriminators + in-provider localization".

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

---

# Follow-up 2026-08-23: same-5-tuple discriminators + in-provider localization

All numbers below are **measured today**, read-only (crafted probe packets only; no
config, node, WireGuard, Cilium or Longhorn change). Method: two privileged
`hostNetwork` netshoot pods per node pair (`netdiag-gr0/gr1/fra0/fra1`, deleted
afterwards) + a raw-socket sender (`IP_HDRINCL`) so the outer 5-tuple could be held
**exactly** equal to the live WireGuard flow (`83.212.173.226:51820 ->
130.162.36.16:51820`) while a single variable was changed. Receiver-side counting used
`tcpdump` filters on magic markers in the payload
(`udp[12:4]=0xdeadbeef` / `0xcafebabe`), so probes are never confused with real WG
traffic (real WG data packets carry a random receiver index).

## Capture-filter trap that invalidated part of the earlier pcap comparison
`fra1`'s `eth0` address is **10.0.1.41** \u2014 Oracle 1:1-NATs the public IP
`130.162.36.16` at the VCN edge. A receiver-side filter containing
`dst host 130.162.36.16` therefore matches **nothing** on fra1 and looks like 100% loss.
Source port *is* preserved by that NAT (verified: fra1-sourced probes with sport 51820
arrive at gr0 with sport 51820). Always filter on `10.0.1.41` (or omit the dst) at fra1.

## New measured facts

### 1. DPI on WireGuard's wire format: EXCLUDED
Interleaved in one run, same 5-tuple, same size (1312 B payload), same rate (50 pps each):

| flow shape | tx @ gr0 eth0 | rx @ fra1 eth0 | loss |
|---|---|---|---|
| WireGuard-shaped (`type=4`, `reserved_zero[3]=0`, receiver index, counter) | 3000 | 2902 | 3.27% |
| non-WG (first byte `0x77`, non-zero reserved, random) | 3000 | 2906 | 3.13% |

Delta = 4 packets, vs binomial sigma ~= 9.6. A DPI classifier keying on WireGuard's
fixed cleartext fingerprint (https://www.wireguard.com/protocol/) cannot produce this.
This is the controlled test the previous report listed as missing.

### 2. Physical-layer bit errors / dirty optics: EXCLUDED
Interleaved, same 5-tuple, same pps, only payload size differing:

| payload | tx | rx | loss |
|---|---|---|---|
| 1312 B | 4500 | 4337 | 3.62% |
| 64 B | 4500 | 4344 | 3.47% |

Frame-corruption loss scales with frame size (~20x here). Loss is flat => not CRC/FEC.

### 3. Loss is Bernoulli, not congestion or a periodic policer
From the 90 s capture pair: 96 loss events, **93 of them single packets** (3 of length 2),
inter-loss gaps geometric (min 2, median 21, max 108), and loss spread evenly over every
5 s bin (1.6%-6.0%). No bursts => no queue overflow; no fixed period => no round-robin
drop.

### 4. Rate dependence: EXCLUDED (not a policer, not congestion)
Same 5-tuple at ~17 kbit/s aggregate (2 flows x 5 pps x 120 s):

| sport | rx | loss |
|---|---|---|
| 51820 | 577/600 | **3.83%** |
| 49000 | 598/600 | 0.33% |

sport 51820 loses 3.3-5.0% at 17 kbit/s, 0.5 Mbit/s and 1 Mbit/s alike, while a
*different source port over the same wire at the same instant* is essentially clean.

### 5. Localization: the drop is INSIDE GRNET, and gr0's host/hypervisor is EXCLUDED
Paris-traceroute-style sweep: fixed 5-tuple per flow class, original TTL encoded in the
IP ID (quoted back in the ICMP time-exceeded), all classes interleaved in randomized
order in one run at identical rate, so ICMP generation rate-limiting affects them
equally.

gr0 -> fra1, 300 probes per cell:

| TTL | responder | sport 40001 (clean bucket) | sport 51820 (live WG bucket) |
|---|---|---|---|
| 2 | 83.212.173.3 (`vlan100-gw2.knossos.grnet.gr`) | 300/300 | **300/300** |
| 3 | 62.217.100.60 | 300/300 | **300/300** |
| 4 | 62.217.100.62 | 300/300 | **289/300 (3.7%)** |
| 6 | 80.81.192.173 (`fra-ix.geant.net`) | 300/300 | 288/300 |
| 8 | 140.91.198.17 (Oracle) | 300/300 | 292/300 |

Consequences (each is now a measured exclusion, not an inference):
- **gr0 guest TX path, vhost, and hypervisor vSwitch: EXCLUDED.** 600 consecutive
  packets of the *lossy* 5-tuple left gr0 and cleared GRNET hops 2 and 3 with zero
  drops. Anything on gr0's host would have dropped ~3.5% of those too. This retires
  hypothesis #1 ("post-capture guest/hypervisor TX path") from the previous report.
- **DE-CIX/GEANT and Oracle VCN ingress / fra1 host: EXCLUDED for this direction.**
  Loss is already present at hop 4, upstream of both.
- **ICMP rate limiting as an artifact: EXCLUDED.** Clean-bucket controls to the *same*
  responder at the same rate in the same run returned 300/300.

### 6. It is NOT the visible ECMP topology, and NOT host-side ECMP
gr0 has a single default route (`default via 83.212.173.1 dev eth0 proto dhcp`), next-hop
MAC `cc:47:52:4e:45:54` = ASCII **"GRNET"** (a platform-provided virtual gateway), and
`fib_multipath_hash_policy=0`. So the per-source-port path split is entirely GRNET's.
GRNET hashes the 5-tuple across two access routers (`83.212.173.2`/`.3`) and >=4 core
next-hops (`62.217.100.54/.58/.60/.76`), but **loss does not follow that split**:

| sport | hop2 | hop3 | hop4 | end-to-end loss |
|---|---|---|---|---|
| 51820 | .173.3 | 62.217.100.60 | 62.217.100.62 | 4.5-5.0% |
| 40009 | .173.3 | 62.217.100.60 | 62.217.100.62 | 5.0% |
| 40001 | .173.3 | 62.217.100.60 | 62.217.100.62 | ~1% |
| 40005 | .173.3 | 62.217.100.60 | 62.217.100.62 | ~1% |
| 40007 | .173.3 | 62.217.100.60 | 62.217.100.62 | ~1% |

Identical router-level path, order-of-magnitude different loss => the faulty element is
**below traceroute resolution**: one member of a link bundle (LAG), or a per-hash
forwarding/inspection element, inside GRNET.

### 7. Destination-independent, and not gr0-specific
- Same probe pattern toward `152.70.165.139` (fra0, different Oracle tenancy) and
  `8.8.8.8` produces the same picture: several buckets lose 2-6% at
  `62.217.100.62`/`.58`/`.76` while interleaved controls are 200/200. The fault is
  therefore GRNET-internal, not tied to the Oracle prefix or the DE-CIX peering.
- **gr1** (83.212.175.41, different GRNET subnet, different hop 2/3:
  `83.212.175.2` -> `62.217.100.100`) also loses **192/200 (4%)** for its lossy bucket
  (sport 40001) at the *same* `62.217.100.62`, with 200/200 for a clean bucket. Two
  independent VMs on different access segments converge on the same device.

### 8. Both directions are affected, on different buckets
fra1 -> gr0, 300 probes each: sport 51820 = **300/300 (clean)**, sport 49000 =
**286/300 (4.7% loss)**. The direction asymmetry in the original report is a
*per-bucket* artifact, not a property of a direction: each direction hashes differently,
and the live WG flow happens to sit in a bad bucket outbound and a good one inbound.

### 9. No single WireGuard listen port is safe for all peers
End-to-end scan, 18 candidate source ports x 300 packets, toward both Oracle peers:

| sport | loss -> fra1 | loss -> fra0 |
|---|---|---|
| 49000 | 0.3% | 1.3% |
| 41000 | 0.7% | 1.7% |
| 55000 | 2.3% | 1.3% |
| 51000 | 2.0% | 1.7% |
| **51820 (current)** | **5.0%** | 2.0% |
| 51821 | 9.3% | 0.3% |
| 40005 | 2.0% | 9.7% |

No scanned port was clean toward both, and the bad-bucket set was not identical between
scan runs hours apart (only 51820's badness was stable across all 5 runs today). This
confirms the earlier warning: **do not blindly re-point gr0's global WireGuard port.**

## Revised conclusion (what is now proven vs inferred)
**Proven:** a persistent, flow-hash-selective, ~4% Bernoulli packet drop that is
independent of packet size, payload shape and offered rate, located inside GRNET within
4 hops of gr0 (first observable at `62.217.100.62`), affecting both gr0 and gr1, in both
directions on different hash buckets. Host, hypervisor, WireGuard, Cilium, MTU, DPI,
bit errors, policers/congestion, Oracle VCN and fra1 are excluded.

**Inferred (best fit, not proven):** one faulty member of a link bundle / per-hash
forwarding path in GRNET's core around `62.217.100.62`. Size- and rate-independence
argue against a lossy physical link (which would show size-dependent CRC loss) and
against a policer, and favour a forwarding-plane or inspection-plane element that drops a
fixed fraction of the packets steered onto it.

## Provider-side data (goal 3): status
- **Oracle**: no VCN flow logs exist in `infra/` (no `oci_logging` resources), and the
  local `oci` CLI session returns HTTP 401 (expired). Not refreshed: it needs interactive
  / 1Password credentials, and Oracle is already excluded for the failing direction.
  If wanted later, VCN flow logs are only informative for the fra1 -> gr0 direction.
- **GRNET**: no API/telemetry access from here. This is where the evidence points, so the
  ticket below is the only route to their queue/LAG-member counters.

## Updated GRNET ticket text (supersedes the earlier evidence pack)
```
Source VM 83.212.173.226 (and 83.212.175.41) -> any external destination.
~4% packet loss on SPECIFIC 5-tuples, while other 5-tuples over the same
routers at the same instant are clean.

Measured, with interleaved clean/lossy controls in every run:
- Loss first appears at TTL 4, responder 62.217.100.62, for both VMs, which
  reach it via different hop-3 routers (62.217.100.60 and 62.217.100.100).
  TTL 2 (83.212.173.3 / 83.212.175.2) and TTL 3: 300/300 and 200/200 clean for
  the SAME lossy 5-tuple => loss is not on our VM/host, and not on the access hop.
- Independent of destination: reproduces toward 130.162.36.16, 152.70.165.139
  and 8.8.8.8.
- Independent of packet size (3.62% @1312B vs 3.47% @64B, interleaved).
- Independent of offered rate (3.8% at 17 kbit/s; 3.3% at 1 Mbit/s).
- Independent of payload (WireGuard-shaped vs random bytes: 3.27% vs 3.13%).
- Bernoulli single-packet drops (93 of 96 events = 1 packet), not bursty.
- ICMP echo is clean; only per-5-tuple UDP/TCP flows are affected, so
  ping-based monitoring shows green.
Please check for a degraded member in the link bundle(s) terminating on
62.217.100.62 (per-member error/discard counters), and any per-hash
inspection/scrubbing element in that path.
```

## Placement guidance stands (unchanged, not applied)
The volume `pvc-92ddd557-...` is currently **detached**, with a single stopped replica on
fra1, `numberOfReplicas=2`, cluster `replica-soft-anti-affinity=false`, and
`engine-replica-timeout={"v1":"8","v2":"8"}` (the log's 16 s is the doubled value). gr0's
`mainpool` v1 filesystem disk is now **schedulable with 428 GiB free**, so the earlier
`LocalReplicaSchedulingFailure` no longer applies and an engine-local replica on gr0 is
schedulable. Nothing was changed; recommendation unchanged from the main report: format /
migrate with engine and its only RW replica on the SAME node, then scale replicas up.

## Reproduction assets
Probe scripts used (raw-socket senders, ~60 lines each, no dependencies) are described
inline above: (a) same-5-tuple interleaved payload/size discriminator, (b) IP-ID-encoded
TTL sweep with interleaved source-port classes, (c) multi-source-port loss scan. All
diagnostic pods (`netdiag-gr0/gr1/fra0/fra1`) and the temporary flattened kubeconfig were
removed after the run.

## Addendum 2026-08-23b: which node pairs are actually affected, and reconciliation
### with the original TCP numbers

### Full tunnel matrix (this is the number Longhorn actually feels)
UDP probes **inside `wg0`** (so each cell is that pair's real WireGuard 5-tuple),
2000 packets @400 pps @200 B per ordered pair, receiver-side counted with `tcpdump -i wg0`.
Rows = sender:

|        | ->gr0 | ->gr1 | ->srv0 | ->fra0 | ->fra1 |
|--------|------|------|-------|-------|-------|
| **gr0**  | -    | 0.0% | **3.9%** | 0.0% | **4.5%** |
| **gr1**  | 0.0% | -    | 0.0%  | 0.0% | 0.0%  |
| **srv0** | 0.0% | 0.0% | -     | 0.0% | 0.0%  |
| **fra0** | 0.0% | 0.3% | 0.0%  | -    | 0.0%  |
| **fra1** | 0.0% | 0.2% | 0.0%  | 0.0% | -     |

Conclusions:
- **srv0 and the Oracle nodes are NOT affected as senders.** fra0 <-> fra1 is 0/2000 in
  both directions; every srv0 path is clean. Oracle-to-Oracle replication is healthy.
- The damage is confined to **gr0's egress, on 2 of its 4 peer tunnels** (fra1 and srv0).
  **gr0 -> gr1 and gr0 -> fra0 are clean**, and everything *inbound to gr0* is clean.
- This is the bucket model confirmed operationally: gr0 uses one WireGuard source port
  (51820) for every peer, so its four tunnels differ only in destination IP, and two of
  them landed in bad hash buckets.
- Note the refinement vs the section above: gr1 has lossy *probe* buckets on the public
  underlay, but its four real tunnel 5-tuples are all currently clean. Bucket badness is
  per-5-tuple luck; only gr0 drew bad ones for real tunnels.

### The original TCP numbers and today's loss numbers are the same fault
A single TCP stream under random loss is loss-limited, not bandwidth-limited:
`BW ~= MSS/RTT * sqrt(1.5/p)`. On wg0, MSS = 1420-40 = 1380 B and measured RTT
gr0->fra1 = **52.9 ms**. At p = 0.045 this predicts **1.20 Mbit/s**. Measured today:

```
gr0 -> fra1 over wg0:  1.15 Mbit/s, 37 retransmits in 10 s   (original report: 1.25 Mbit/s, 35 retx)
gr0 -> fra0 over wg0: 47.80 Mbit/s, 9051 retransmits in 10 s
```

So the original "1.25 Mbit/s / 35 retx" and today's "4.5% UDP loss" are two views of one
fault, and the original retransmit counts were already a loss measurement:
4 MiB ~= 3473 segments, so 130-145 retx = **3.7-4.2%**, matching today's 3.3-5.0%.
The 4 MiB / 35-40 s that broke `mke2fs` follows directly.

The fra0 comparison is instructive and rules out a shared bottleneck: that path reaches
47.8 Mbit/s and only sheds packets when pushed hard (rate-dependent = ordinary
congestion), whereas fra1 collapses to ~1 Mbit/s because its loss is a fixed ~4.5%
probability present even at 17 kbit/s. Different mechanisms; only the latter breaks
Longhorn.

The single unexplained legacy datapoint remains the early "373 Mbit/s with 1542 retx"
sample, which is inconsistent with every later measurement and stays flagged as anomalous.

### Practical consequence for placement (still not applied)
Only **gr0** is degraded, and only as a sender toward **fra1** and **srv0**. Therefore:
- Any engine/replica pair among {gr1, srv0, fra0, fra1} is currently on a clean path.
- gr0 as engine with its replica on **fra0** is currently clean too (0/2000, 47.8 Mbit/s),
  though it is one hash-bucket reroll away from degrading, so engine-local replicas remain
  the durable answer.
- The combinations to avoid are exactly gr0-engine + sole replica on **fra1** or **srv0**,
  which is precisely what this incident hit.

## Addendum 2026-08-23c: why attach fails for *these* PVs specifically

Three conditions must coincide. Only one volume in the cluster meets all three.

### 1. Engine node -> sole-RW-replica node must be one of gr0's two broken tunnels
All five RWX volumes, checked against the measured matrix:

| volume | claim | engine (sm ownerID) | replicas | measured path loss | outcome |
|---|---|---|---|---|---|
| pvc-92ddd557 | netmaker/netmaker-dns-pvc | **gr0** | **fra1** | **4.5%** | **fails** |
| pvc-f0f2e998 | netmaker/netmaker-dns-pvc-old | gr0 | fra0 | 0.0% | fine |
| pvc-d4c3a848 | netmaker/netmaker-k8s-ops-netclient-pvc | fra1 | srv0, fra1 | 0.0% | fine |
| pvc-089994af | netmaker/...netclient-pvc-old | fra1 | fra0 | 0.0% | fine |
| pvc-c8dd916d | netmaker/netmaker-shared-data-pvc | srv0 | fra0 | 0.0% | fine |

5/5 correlation, and the Woodpecker throwaway PVCs fit as well (consumer on gr0, sole
replica on **srv0** = the other 3.9% path). Note gr0 itself is not cursed: gr0 + fra0
is currently a clean path.

### 2. RWX turns a data-path fault into an *attach* failure
For RWX, Longhorn must format the volume and start NFS-Ganesha **inside the
share-manager** before the share exists. So a synchronous-write failure surfaces as
`Waiting for volume share to be available` during attach, not as an I/O error. The same
underlying fault on an RWO volume would appear *after* a successful mount as `EIO`.
That is why the failure class looks like "attach is broken" rather than "the network is
lossy".

### 3. The volume cannot self-heal out of it (the actual deadlock)
- `spec.numberOfReplicas=2` but only **one** replica has ever existed
  (`r-cc7843a2`, fra1, created 2026-08-22T01:14:56Z, i.e. 2 s after the volume).
- The volume's condition is `Scheduled=True`, message *"Reset schedulable due to allow
  volume creation with degraded availability"*, and
  `allow-volume-creation-with-degraded-availability=true` -> it was **created 1-of-2**
  because gr0's disk was unavailable at that moment (the `LocalReplicaSchedulingFailure`
  in the main report).
- A missing replica is replenished by an engine-driven rebuild, which requires the volume
  to be **attached and healthy**. Attaching requires mkfs to succeed. mkfs requires a
  backend that answers within the replica timeout. The only backend is across the 4.5%
  path. => circular.
- Nothing breaks that circle in the background: `offline-replica-rebuilding=false`
  (volume-level: `ignored`) and `replica-auto-balance=disabled`, so while the volume is
  detached the second replica will never be created.
- gr0's `mainpool` v1 disk is **now** schedulable with 428 GiB free and all
  node/disk conditions are healthy, so the deadlock is breakable on demand - it just
  never breaks itself.

### Timeout arithmetic, for completeness
`engine-replica-timeout={"v1":"8"}` (the engine log's "No response received in 16s" is
the doubled value). A 4 MiB journal write at the loss-limited ~1.15 Mbit/s takes ~29-40 s,
so it exceeds even the 30 s maximum setting. Raising the timeout cannot fix this volume;
only replica placement or a fixed network path can.

### Not determined
What put this volume's share-manager on gr0. The ShareManager CR carries no node field
(`spec` holds only `image`; `status.ownerID=gr0`), `rwx-volume-fast-failover=true`, and no
share-manager pod exists right now to inspect its scheduling constraints. So "engine lands
on gr0" is currently an observed outcome, not an understood mechanism - worth pinning down
before relying on placement as the mitigation.
