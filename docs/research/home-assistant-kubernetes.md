# Home Assistant OS to Kubernetes: feasibility and migration architecture

Research date: **2026-09-18**. This is a research note only; it makes no infrastructure changes. Sources are restricted to Home Assistant, Kubernetes, protocol standards, and first-party project documentation/source repositories.

## Scope and snapshot

The starting point is **Home Assistant OS (HA OS)** with **ZHA** and an ITead **SONOFF ZBDongle-E (EFR32MG21 / EmberZNet)** coordinator. Home Assistant's current ZHA documentation explicitly lists that dongle as a tested EZSP/EmberZNet adapter. [Evidence: HA ZHA hardware compatibility](https://www.home-assistant.io/integrations/zha/#other-tested-and-compatible-zigbee-adapters).

The source snapshots examined were Home Assistant documentation commit [`2ed0167` (2026-09-18)](https://github.com/home-assistant/home-assistant.io/commit/2ed01678090ef825bca982db7b69882d98477326), Zigbee2MQTT `2.14.1` source commit [`3c3d8c1` (2026-09-03)](https://github.com/Koenkk/zigbee2mqtt/commit/3c3d8c1a71cabb31f1b97ad268681dd3f747ce19), zigbee-herdsman `10.9.4` commit [`e9dcfb5` (2026-09-18)](https://github.com/Koenkk/zigbee-herdsman/commit/e9dcfb5c5967fb8b279c92e4fd0afe3173c06124), and `przemekhys/homeassistant-operator` `main` commit [`e9a7f81` (2026-09-18)](https://github.com/przemekhys/homeassistant-operator/commit/e9a7f8189f934a2e8b4054eead18caee5b21eb56).

## Executive conclusion

**Feasible, but it is a trade of HA OS convenience for Kubernetes operations, not a supported HA OS equivalent.** Home Assistant recommends HA OS for most users; HA OS includes Home Assistant Core and Supervisor and supports apps (the current name for add-ons). Home Assistant Container is an officially documented installation type, but it has no apps and requires the operator to supply the host/container platform and updates. [Official installation comparison](https://www.home-assistant.io/installation/#about-installation-types), [HA OS/Supervisor and apps terminology](https://www.home-assistant.io/getting-started/concepts-terminology/#apps), [official Container installation](https://www.home-assistant.io/installation/linux/#install-home-assistant-container).

### Recommendation

1. **Migrate HA first, not Zigbee:** run the official Home Assistant Container image as one pinned, stateful Kubernetes workload; retain ZHA, the existing ZBDongle-E, and its ZHA data during this move. [Container support](https://www.home-assistant.io/installation/linux/#install-home-assistant-container), [ZHA recovery/migration](https://www.home-assistant.io/integrations/zha/#backups-and-migration)
2. **Initially pin the HA pod to the USB-owning node.** Mount the persistent `/config` volume and only the stable `/dev/serial/by-id/...` coordinator path. Do not permit a second HA or Zigbee process to open the coordinator. [Container device mapping](https://www.home-assistant.io/installation/linux/#install-home-assistant-container), [Kubernetes character devices](https://kubernetes.io/docs/concepts/storage/volumes/#hostpath)
3. **Use host networking initially** if discovery across the current LAN is needed; verify every required discovery integration and VLAN from that exact node. Host networking is a compatibility measure, not VLAN routing or multicast reflection. [HA Zeroconf behavior](https://www.home-assistant.io/integrations/zeroconf/), [mDNS link-local standard](https://www.rfc-editor.org/rfc/rfc6762.html#section-3)
4. **Treat HA recovery as single-writer cold/warm failover, not active-active HA.** A storage/node failure can restart the one pod elsewhere only after its volume and, while USB is used, its coordinator are available. It cannot safely create a second live HA instance on the same state. [Recorder state](https://www.home-assistant.io/integrations/recorder/), [single-pod PVC access](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes)
5. **Keep ZHA→Zigbee2MQTT as a separately tested future project.** It can technically preserve pairings using the shared Open Coordinator Backup format, but it is not a documented, supported end-to-end migration. Do not combine that risk with the HA OS migration. [Open Coordinator Backup](https://github.com/zigpy/open-coordinator-backup/blob/main/README.md), [ZHA-only migration procedure](https://www.home-assistant.io/integrations/zha/#migrating-to-a-new-zigbee-adapter-inside-zha)

This approach accepts the user's initial pinning constraint while leaving a future clean seam: a separately stateful Zigbee2MQTT service, a durable MQTT broker, and a **wired Ethernet** coordinator can remove the USB/node affinity from HA. It does not make Zigbee itself multi-writer or highly available.

**ZHA itself cannot be split into another pod:** it is an [integration running inside Home Assistant Core](https://www.home-assistant.io/integrations/zha/). Decoupling the Zigbee process from HA requires another Zigbee application such as Zigbee2MQTT (plus MQTT) or deCONZ. A network coordinator removes HA's *node* affinity while retaining ZHA, but ZHA still stops whenever HA stops. This distinction determines whether the desired failure-domain separation is worth the risk of a later ZHA→Zigbee2MQTT migration.

## 1. What is officially supported by Home Assistant

### Evidence

- HA OS is the recommended installation type and supports apps. Home Assistant Container is supported as a container installation, but users manage its surrounding system/orchestration and updates; it has no apps. The official comparison specifically calls out Thread and Z-Wave as integrations without out-of-the-box Container support because they are normally controlled by apps. [Official installation types](https://www.home-assistant.io/installation/#about-installation-types).
- The official Container guide uses the Home Assistant image, a host directory mounted at `/config`, `--network=host`, and a 60-second shutdown grace period in its Compose example. It documents explicit device mapping for Zigbee and other `/dev/tty*` integrations. [Container guide](https://www.home-assistant.io/installation/linux/#install-home-assistant-container).
- HA's installation-independent backup UI applies to all installation types, and the Container-specific common-tasks page directs users to it for backup and restore. Backups are compressed archives, encrypted by default, and may be restored selectively. [Backups](https://www.home-assistant.io/common-tasks/general/#backups), [Container common tasks](https://www.home-assistant.io/common-tasks/container/#backup).

### Recommendation and implication

Kubernetes is **not** an HA OS deployment mode. The supported component inside the cluster is Home Assistant Container; Supervisor and HA OS app management do not come with it. Before migration, inventory every HA OS app and choose one of: an independently maintained Kubernetes workload, a managed external service, or removal. Do not expect an HA OS backup's app selection to become Kubernetes workloads automatically.

Use the official `ghcr.io/home-assistant/home-assistant` image, pin an explicit tested HA release rather than `stable`, and own the lifecycle and compatibility testing. This follows the Container model while avoiding a mutable deployment input. The Home Assistant project's own Container instructions also show why a termination grace period matters: it warns that premature termination can leave the SQLite recorder uncleanly shut down. [Container shutdown guidance](https://github.com/home-assistant/home-assistant.io/blob/2ed01678090ef825bca982db7b69882d98477326/source/_includes/installation/container.md#L65-L100).

No first-party Home Assistant Helm chart or operator is listed by the official installation documentation. Therefore, a minimal Kubernetes `StatefulSet`/PVC based directly on the official image is the lowest-extra-abstraction Kubernetes pattern; it is not an official HA Kubernetes support commitment.

## 2. Recommended Kubernetes shape and its limits

### Evidence

- The Recorder's default and recommended database is SQLite, located as `home-assistant_v2.db` in `/config`; Home Assistant warns that changing recorder database is not a supported history migration. [Recorder documentation](https://www.home-assistant.io/integrations/recorder/).
- A Kubernetes StatefulSet is intended to provide stable identity and stable storage. Kubernetes documents `ReadWriteOncePod` as single-pod writable access and recommends it for production StatefulSet storage where available; ordinary `ReadWriteOnce` limits write mounting to a node, not necessarily one pod on that node. [StatefulSet](https://kubernetes.io/docs/concepts/workloads/controllers/statefulset/), [PersistentVolume access modes](https://kubernetes.io/docs/concepts/storage/persistent-volumes/#access-modes).
- Kubernetes `hostPath` has a `CharDevice` type for a Linux character device, while device plugins are Kubernetes' general mechanism for advertising vendor-specific hardware to pods. [hostPath types](https://kubernetes.io/docs/concepts/storage/volumes/#hostpath), [device plugins](https://kubernetes.io/docs/concepts/extend-kubernetes/compute-storage-net/device-plugins/).

### Recommended workload

- One `StatefulSet`, **one replica**, one PVC mounted at `/config`, and a pre-stop/termination grace period long enough for HA to close its recorder.
- Prefer a CSI-backed **ReadWriteOncePod** PVC if this cluster's storage driver supports it. Otherwise use RWO with a strict `replicas: 1` operational rule. Do not use RWX to run multiple HA writers.
- Request/limit CPU and memory based on observed use; prevent voluntary disruption while the maintenance plan is not prepared. Snapshot the PVC only with a documented restore exercise; an application backup copied off-cluster remains the recovery artifact.
- Label/taint the coordinator node and use required node affinity or a node selector. Mount the USB device by its `/dev/serial/by-id/` path, not a volatile `/dev/ttyUSB0`/`ttyACM0` name. `hostPath` plus node pinning is adequate for this single known dongle; a device plugin is preferable only if the cluster must schedule many exclusive hardware devices.
- Expose the UI through the normal ingress/gateway path or a Service, but do not mistake an HTTP load balancer for discovery networking or HA clustering.

### Realistic availability

Home Assistant's documented Container model and default local SQLite recorder provide no active-active/clustered HA model. The single-PVC and single-coordinator design above is deliberately **one writer**. An external recorder database can reduce the amount of state on the PVC, but it does not cluster HA configuration, `.storage` state, integrations, USB ownership, discovery sockets, or the Zigbee controller; Recorder also says history migration between database engines is unsupported. [Recorder database behavior](https://www.home-assistant.io/integrations/recorder/).

**Recommendation:** define success as automated restart of *one* HA pod after a process failure and rehearsed restoration after a PVC/node loss. Do not claim zero downtime or active-active failover. With direct USB, a different node cannot run ZHA until the coordinator is physically available there. With a network coordinator, HA can be restarted on another eligible node, but the remote coordinator, Zigbee2MQTT (if used), MQTT broker, routing, credentials, and the one HA PVC must still be healthy.

## 3. HA OS → Kubernetes state, backup, and cutover plan

### Evidence

- Home Assistant backups exist specifically to restore a system or migrate it to new hardware. They can be stored off the appliance, downloaded, and restored during onboarding or selectively on an existing system. Encryption requires preserving the backup emergency-kit key. [Official backup and restore process](https://www.home-assistant.io/common-tasks/general/#backups).
- Creating an HA backup invokes ZHA's pre-backup hook, which asks ZHA/zigpy to create a network backup including devices. [ZHA backup hook source](https://github.com/home-assistant/core/blob/dev/homeassistant/components/zha/backup.py#L12-L24).
- ZHA documents that, after restoring an HA backup, ZHA can be reconfigured or migrated to another coordinator without loss of connected-device settings, and that manual coordinator backups are available under ZHA Network Settings. [ZHA backups and migration](https://www.home-assistant.io/integrations/zha/#backups-and-migration).

### Recommended sequence

1. **Inventory and freeze the scope.** Record HA version, every HA OS app, integrations requiring LAN discovery, custom components, secrets, external media, the current ZHA radio path, coordinator IEEE/PAN/channel, and all VLANs/devices that must work. Export/retain the HA backup encryption key.
2. **Make and validate recovery artifacts.** Create a full HA backup with ZHA running, copy it to an off-cluster location, and verify it can be opened/restored in a disposable test target. Also protect the Long-Term Statistics/history expectation explicitly: keep the SQLite database if history is wanted, or accept its loss rather than attempting an unsupported recorder-engine migration.
3. **Prepare but do not start the destination**: one pinned Home Assistant Container pod, persistent `/config`, coordinator node pin, device access, selected discovery networking, TLS/proxy settings, and an off-cluster backup destination. Recreate HA OS apps as independently operated services before relying on their integrations.
4. **Cut over with one writer.** Stop HA OS fully before the Kubernetes pod receives the ZBDongle-E. Make the final backup, retain an immutable copy, move the dongle, restore the HA configuration/selected backup contents, and reconfigure ZHA to its moved device path. Never allow HA OS/ZHA and the pod/ZHA to hold the same serial device concurrently.
5. **Acceptance test before retirement.** Check login/users, config validation, automations, recorder/history expectation, ZHA device count and control, paired-device reactions after a restart, MQTT/cloud integrations, ingress WebSocket behavior, and every required discovery/VLAN. Keep HA OS powered off but recoverable until this succeeds.
6. **Operate backups independently of the PVC.** Schedule HA backups to an external backup location and separately protect the PVC/snapshots. Test restoration to a fresh namespace/PVC, including the encryption key; a backup archive left only under `/config` is lost with that volume.

## 4. ZHA and the current SONOFF ZBDongle-E

### Preserve pairings for the initial move

The least-risk route is **HA OS ZHA → HA Container ZHA with the same ZBDongle-E**. It uses the official ZHA restore/reconfigure path rather than changing Zigbee implementations. The existing dongle is explicitly an EmberZNet/EZSP model supported by ZHA, and ZHA's documented backup path is designed to retain/recover the network or migrate it. [ZHA hardware list](https://www.home-assistant.io/integrations/zha/#other-tested-and-compatible-zigbee-adapters), [ZHA backup/migration procedure](https://www.home-assistant.io/integrations/zha/#migrating-to-a-new-zigbee-adapter-inside-zha).

If the radio itself must change while retaining ZHA, ZHA officially supports migration among Silicon Labs, Texas Instruments, and ConBee/RaspBee adapters when the backup was created in ZHA. It may request an IEEE-address overwrite; the documentation says that skipping the IEEE migration can require reconnecting many devices. [ZHA migration steps and prerequisites](https://www.home-assistant.io/integrations/zha/#migrating-to-a-new-zigbee-adapter-inside-zha).

### USB and scheduling recommendation

Use the stable `/dev/serial/by-id` path passed into the pod and pin the pod to that host. Home Assistant's Container guide explicitly requires mapping the device into the container for Zigbee; Kubernetes supplies the equivalent `hostPath`/character-device and scheduling primitives. [HA Container device mapping](https://github.com/home-assistant/home-assistant.io/blob/2ed01678090ef825bca982db7b69882d98477326/source/_includes/installation/container.md#L123-L147), [Kubernetes hostPath `CharDevice`](https://kubernetes.io/docs/concepts/storage/volumes/#hostpath).

This is an availability boundary: the volume can move, but the direct USB radio cannot. A Kubernetes restart on an unpinned node is not a ZHA failover.

### Network-attached ZBT/EZSP: direct answer

- **ZBT-1/ZBT-2 are documented as USB adapters**, not Ethernet coordinators. Their official-ZHA listing does not establish an officially recommended network-attached ZBT deployment. [ZHA official hardware section](https://www.home-assistant.io/integrations/zha/#recommended-official-home-assistant-hardware).
- ZHA does support socket URLs for network-connected adapters and documents `socket://IP:port` for ZBBridge/ZiGate cases; its network-information UI also recognizes a socket URL for a network/Ethernet adapter. [ZHA configuration](https://www.home-assistant.io/integrations/zha/#zigate-or-sonoff-zbbridge-devices), [ZHA network information](https://www.home-assistant.io/integrations/zha/#about-network-information).
- However, HA explicitly warns against a Serial-to-IP/Ser2Net coordinator over **Wi-Fi, WAN, or VPN**, because coordinator serial protocols require a stable connection and are not fault tolerant to drops/latency. It separately calls Wi-Fi ZBBridge use not recommended for EZSP. [ZHA hardware caveat](https://www.home-assistant.io/integrations/zha/#supported-but-not-recommended-zigbee-adapters).

**Recommendation:** do not turn the existing USB ZBDongle-E into a Wi-Fi/WAN/VPN serial proxy. A wired-Ethernet proxy is not prohibited by that warning, but HA does not document it as the recommended ZBT/ZBDongle-E design; treat it as a lab proof-of-concept with loss/reconnect testing, not as the initial migration path. A purpose-built wired coordinator is a more credible future direction, particularly if Zigbee2MQTT is adopted.

## 5. Can ZHA → Zigbee2MQTT preserve pairings?

### Answer

**Technically, current first-party code provides a compatible path for an Ember/EFR32 network backup; operationally, neither project documents a supported end-user ZHA→Zigbee2MQTT migration.** Thus it is reasonable to say *pairings can potentially be preserved*, not that this is a guaranteed migration procedure for this installation.

### Evidence for technical compatibility

1. The [Open ZigBee Coordinator Backup specification](https://github.com/zigpy/open-coordinator-backup/blob/main/README.md) exists specifically to move Zigbee network information between coordinator hardware **and network-management software without rejoining devices**. It lists both zigpy (used by Home Assistant) and zigbee-herdsman (used by Zigbee2MQTT) as adopters.
2. Zigpy can export its `NetworkBackup` as that `zigpy/open-coordinator-backup` JSON format, including network key, PAN IDs, channel, device addresses/link keys, and stack-specific data. [zigpy export implementation](https://github.com/zigpy/zigpy/blob/512f3cfdb6ee049481c792f326343c575b3181f6/zigpy/backups.py#L247-L339).
3. For the EFR32/Ember stack, bellows—the zigpy radio library ZHA uses—records `stack_specific.ezsp.hashed_tclk` and `metadata.internal.ezspVersion`; its source comments that Zigbee2MQTT requires that internal key. [bellows EFR32 backup state](https://github.com/zigpy/bellows/blob/15ccb49622af2e60b389ff7a5f86e32fef82d626/bellows/zigbee/application.py#L385-L431).
4. Zigbee2MQTT starts zigbee-herdsman with `coordinator_backup.json` and the configured PAN ID, extended PAN ID, channel, and network key. [Zigbee2MQTT startup source](https://github.com/Koenkk/zigbee2mqtt/blob/3c3d8c1a71cabb31f1b97ad268681dd3f747ce19/lib/zigbee.ts#L31-L60). Its Ember adapter accepts version-1 Open Coordinator Backup JSON only when `stack_specific.ezsp` and `metadata.internal.ezspVersion` are present and EZSP is at least v12; it then imports link keys and forms from that backup when the configured network values match. [zigbee-herdsman Ember restore validation](https://github.com/Koenkk/zigbee-herdsman/blob/e9dcfb5c5967fb8b279c92e4fd0afe3173c06124/src/adapter/ember/adapter/emberAdapter.ts#L1147-L1173), [restore path](https://github.com/Koenkk/zigbee-herdsman/blob/e9dcfb5c5967fb8b279c92e4fd0afe3173c06124/src/adapter/ember/adapter/emberAdapter.ts#L925-L1002).
5. Zigbee2MQTT documents the values that must not change—network key, PAN ID, extended PAN ID, and channel—and says changing the network key requires re-pairing. [Zigbee2MQTT network configuration](https://www.zigbee2mqtt.io/guide/configuration/zigbee-network.html). It also documents that moving an existing **Zigbee2MQTT** installation preserves devices by moving its data directory and coordinator path. [Zigbee2MQTT FAQ](https://www.zigbee2mqtt.io/guide/faq/#how-do-i-move-my-zigbee2mqtt-instance-to-a-different-environment).

### Evidence for the support boundary

ZHA's published migration procedure is explicitly **inside ZHA**. Zigbee2MQTT's published migration procedures are for existing Zigbee2MQTT adapters/instances. Neither current first-party procedure describes exporting a ZHA backup, loading it into Zigbee2MQTT, rebuilding HA entities/automations, or rollback. [ZHA migration](https://www.home-assistant.io/integrations/zha/#migrating-to-a-new-zigbee-adapter-inside-zha), [Zigbee2MQTT adapter migration](https://www.zigbee2mqtt.io/guide/faq/#how-do-i-migrate-from-one-adapter-to-another).

### Recommendation

Do **not** make this conversion part of HA OS retirement. If pursued later, make it an explicit experimental change with an offline copy of the HA backup and ZHA/zigpy network backup, a schema check for the required Ember fields above, a fixed/pinned Zigbee2MQTT version, matching network values, and a rollback path to ZHA. Validate actual device control, sleepy devices, bindings/groups, and the rebuilt HA MQTT-discovered entities/automations. Z2M's MQTT discovery creates Home Assistant devices via the MQTT integration, but that is a different HA entity model from ZHA and needs migration testing. [Z2M Home Assistant MQTT discovery](https://www.zigbee2mqtt.io/guide/usage/integrations/home_assistant.html).

## 6. Future decoupling: Zigbee2MQTT plus a wired network coordinator

### Evidence

- Zigbee2MQTT supports TCP network adapters (`tcp://IP:port`), recommends static addressing, and supports mDNS discovery where the adapter implements it. [Zigbee2MQTT adapter settings](https://www.zigbee2mqtt.io/guide/configuration/adapter-settings.html).
- Zigbee2MQTT advises against Wi-Fi network adapters because the serial protocol lacks fault tolerance for packet loss/latency, and recommends a **wired Ethernet** remote adapter if local USB/UART is not possible. [Zigbee2MQTT supported-adapter notes](https://www.zigbee2mqtt.io/guide/adapters/).
- Zigbee2MQTT's Ember documentation lists supported firmware 7.4.x through 9.1.x and network/TCP Ember coordinators. Its `adapter: ezsp` name is deprecated in favour of `adapter: ember`. [Ember adapter documentation](https://www.zigbee2mqtt.io/guide/adapters/emberznet.html).

### Recommendation

For the later design, run **one** separate Zigbee2MQTT workload with its own PVC, the network coordinator's fixed wired IP/DNS name, and a durable MQTT broker. HA connects only to MQTT. This removes HA's USB affinity and lets HA restart on another eligible node while Zigbee2MQTT remains on its own coordinator path.

It is still not Zigbee HA: only one Zigbee2MQTT process may own a coordinator/network at a time, and its PVC/coordinator/broker need their own recovery plans. The important improvement is failure-domain separation—HA failure no longer necessarily interrupts the Zigbee coordinator process—not duplicate controllers.

## 7. Networking, multicast, Avahi, and multiple VLANs

### Evidence

- Home Assistant enables Zeroconf by default, uses it for discovery and to make itself discoverable, and chooses broadcast interfaces through its Network integration. HA auto-detection normally selects the interface used to route to the mDNS multicast address `224.0.0.251`; otherwise it may use all eligible interfaces. [Zeroconf integration](https://www.home-assistant.io/integrations/zeroconf/), [Network integration](https://www.home-assistant.io/integrations/network/).
- Home Assistant enables SSDP discovery by default and listens for broadcast discovery. [SSDP integration](https://www.home-assistant.io/integrations/ssdp/).
- Kubernetes states that `hostNetwork` pods should use `dnsPolicy: ClusterFirstWithHostNet`. [Kubernetes pod DNS policy](https://kubernetes.io/docs/concepts/services-networking/dns-pod-service/#pod-s-dns-policy).
- mDNS `.local` names are link-local by specification and use `224.0.0.251` / `FF02::FB`. [RFC 6762 §§3–4](https://www.rfc-editor.org/rfc/rfc6762.html#section-3). SSDP uses the local-administrative-scope multicast address `239.255.255.250`; its design leaves grouping/scope to the network administrator. [SSDP specification §2.2–2.3](https://www.ietf.org/archive/id/draft-cai-ssdp-v1-03.txt).
- Avahi can deliberately reflect mDNS between local networks when `enable-reflector=yes`; the project warns to avoid multiple reflectors between the same networks. [Avahi reflector documentation](https://github.com/lathiat/avahi/blob/ef903fb0a29bc4394c5a76309405e5a827a4e390/man/avahi-daemon.conf.5.xml.in#L315-L337).

### Recommendation

Start HA with `hostNetwork: true` on the pinned node where LAN discovery matters, plus `ClusterFirstWithHostNet`. This puts HA's discovery sockets in that node's network namespace; it does **not** make a Kubernetes Service/Ingress transport mDNS or SSDP, and it consumes the host port namespace. Keep a normal Service/Ingress for the web UI.

For multiple VLANs, make the network design explicit rather than relying on host networking:

1. Put the selected HA node on, or route it to, each required IoT VLAN; permit the required unicast traffic in both directions.
2. Decide discovery protocol by protocol. mDNS needs an intentional reflector/gateway (for example, a correctly scoped Avahi reflector) because it is link-local. SSDP multicast forwarding/proxying and firewall rules are separate router/switch policy decisions.
3. Limit reflected services/VLANs to the required trust boundary. Discovery across a VLAN is an authorization decision, not merely a connectivity fix.
4. Test from the exact HA node/pod: mDNS browse/advertise, SSDP browse, direct TCP/UDP integrations, MQTT, and callback/webhook paths. If a device has a stable IP or explicit integration endpoint, prefer that over cross-VLAN multicast where practical.

NetworkPolicy deserves special care with host networking: Kubernetes documents that NetworkPolicy handling of `hostNetwork` traffic is implementation-dependent. Do not assume a pod-IP NetworkPolicy isolates the host-networked HA process; enforce the primary boundary in the host/VLAN firewall and test the cluster CNI behavior. [Kubernetes NetworkPolicy and hostNetwork](https://kubernetes.io/docs/concepts/services-networking/network-policies/#networkpolicy-and-hostnetwork-pods).

## 8. Assessment: `przemekhys/homeassistant-operator`

### Evidence: activity and releases

The project is active, not archived: GitHub records creation on 2026-01-05 and a main-branch push on 2026-09-18. [Repository metadata](https://api.github.com/repos/przemekhys/homeassistant-operator), [latest main commit](https://github.com/przemekhys/homeassistant-operator/commit/e9a7f8189f934a2e8b4054eead18caee5b21eb56). Its most recent stable release at this research point is [`v1.4.2`, 2026-09-10](https://github.com/przemekhys/homeassistant-operator/releases/tag/v1.4.2); [`v1.5.0-rc.1`, 2026-09-16](https://github.com/przemekhys/homeassistant-operator/releases/tag/v1.5.0-rc.1) is explicitly a prerelease. Recent GitHub Actions include passing lint, unit tests, Helm, security, CodeQL, and E2E workflows. [E2E run on 2026-09-18](https://github.com/przemekhys/homeassistant-operator/actions/runs/35370011305).

### Evidence: capabilities and architecture

It is a community Kubebuilder operator, not a Home Assistant-owned project. It creates a Home Assistant PVC, single-replica StatefulSet, Service, optional Ingress/Gateway/TLS resources, onboarding/token bootstrap, HA backup scheduling, and CRDs for configuration, secrets, integrations, automations, scenes, scripts, and HA registry objects. Its reconcilers also call the HA REST/WebSocket APIs. [Project architecture](https://github.com/przemekhys/homeassistant-operator/blob/e9a7f8189f934a2e8b4054eead18caee5b21eb56/docs/development/architecture.md), [HomeAssistant API/source](https://github.com/przemekhys/homeassistant-operator/blob/e9a7f8189f934a2e8b4054eead18caee5b21eb56/api/v1/homeassistant_types.go), [reconciler source showing one replica](https://github.com/przemekhys/homeassistant-operator/blob/e9a7f8189f934a2e8b4054eead18caee5b21eb56/internal/controller/homeassistant_controller.go#L503-L508).

The documented compatibility minimum is Kubernetes 1.24; its E2E CI target is k3s 1.36.4 on k3d. It passes a requested HA image tag through and defaults to `stable`. [Compatibility document](https://github.com/przemekhys/homeassistant-operator/blob/e9a7f8189f934a2e8b4054eead18caee5b21eb56/docs/reference/compatibility.md). It supports host networking and maps host device nodes using a `CharDevice` hostPath, but those features live under `spec.alpha`. [API source](https://github.com/przemekhys/homeassistant-operator/blob/e9a7f8189f934a2e8b4054eead18caee5b21eb56/api/v1/homeassistant_types.go#L25-L129).

### Production-readiness signals and concerns

Positive signals are active releases, signed artifacts, source-visible tests, e2e workflow, documented architecture, and a defined compatibility page. These justify evaluation in a lab; they are not production evidence for this homelab's USB, CNI, storage, and VLAN combination.

The project is also young and lightly adopted: at the snapshot date GitHub reports creation in January 2026, 17 stars, one fork, and no subscribers. Those numbers do not measure code quality, but they do mean there is little public evidence of broad operational use. [Repository metadata](https://api.github.com/repos/przemekhys/homeassistant-operator).

The strongest technical negative signal is the operator's own lifecycle policy: device passthrough and NetworkPolicy are alpha, may change or disappear in a minor release with no deprecation, and its documentation says physical dongles and real CNIs cannot be proven in CI. [Alpha lifecycle](https://github.com/przemekhys/homeassistant-operator/blob/e9a7f8189f934a2e8b4054eead18caee5b21eb56/docs/explanation/alpha-lifecycle.md). In addition, its declared E2E environment is k3s-on-k3d, not physical USB, HA OS migration, multicast/VLAN routing, or storage failover. [Compatibility scope](https://github.com/przemekhys/homeassistant-operator/blob/e9a7f8189f934a2e8b4054eead18caee5b21eb56/docs/reference/compatibility.md).

### Recommendation

**Do not make this operator the initial migration dependency.** The initial plan needs no CRDs or controller that manages HA through a bootstrap token, rewrites configuration sources, and owns the StatefulSet/PVC. Use a small direct official-image StatefulSet and prove HA/ZHA/network recovery first.

Reconsider the operator only if declarative management of HA configuration/automations/integrations is a concrete later goal. Then pin a released version (not `stable`/an RC), use a disposable namespace, review its CRD ownership/restore behavior, test this exact USB and host-network/VLAN setup, and adopt no alpha device/network features without a rollback plan. It is a credible active community project, but its own evidence does not justify treating it as a mature HA/failover solution.

## 9. Concrete fit for this homelab repository

This section is based on the checked-in configuration, not live-cluster discovery: the local `kubectl` configuration had no current context during this review.

### Existing primitives that fit

- Both `srv0` (`10.13.37.120`) and `srv1` (`10.13.37.121`) are declared as homelab RKE2 agents. `srv1` is ARM64; Home Assistant publishes the Container installation for 64-bit systems including AArch64. [Node definitions](../../nixos/flake.nix#L6-L7), [official Container requirements](https://www.home-assistant.io/installation/linux/#prerequisites)
- RKE2 currently labels nodes only by provider/zone, so both local nodes look like `provider=homelab`; there is no checked-in hardware label for the dongle. Add a dedicated label such as `home-assistant.io/zigbee-coordinator=true` to the one USB-owning node and require it in the workload. Do not select merely `provider=homelab`. [Current node labels](../../nixos/rke2/config.nix#L20-L25)
- The appropriate existing storage class is `longhorn-v1`: it is the default, uses the deliberately selected v1 engine, retains deleted PVs, creates two replicas, and uses best-effort data locality. Use a single RWO claim for `/config` (or RWOP only after confirming the installed Longhorn CSI version supports it); do not use the throwaway class or RWX as a way to run two HA pods. [Storage class definition](../../envs/longhorn/main.jsonnet#L97-L118)
- This repository already uses Tanka/Jsonnet environments and direct StatefulSets. A small `envs/home-assistant` environment is consistent with the repository and avoids introducing an operator solely to generate one StatefulSet, Service, and PVC.

### Networking issue that must be fixed before discovery testing

The checked-in NixOS firewall enables filtering but globally opens only the WireGuard UDP port; its RKE2 rules open TCP 80/443 and trust CNI ingress, not LAN multicast UDP. [Base firewall](../../nixos/system/network.nix#L34-L41), [RKE2 firewall](../../nixos/rke2/firewall.nix#L19-L38). A host-networked HA process may therefore send traffic yet fail to receive unsolicited mDNS (`UDP/5353`) or SSDP (`UDP/1900`) arriving on the physical/VLAN interfaces. Add narrowly scoped input rules for the required multicast groups, ports, interfaces, and source VLANs, then verify with packet capture. Do not simply expose HA's TCP/8123 to every interface; Traefik can remain the UI entry point.

The repository configures DHCP and a primary `eth0`, but it does not declare VLAN subinterfaces or an Avahi reflector on the Kubernetes nodes. [Host network configuration](../../nixos/system/network.nix#L17-L32). Therefore, the statement that both nodes can *route to* both VLANs proves unicast reachability, not mDNS/SSDP reachability. Put reflection/forwarding on the router or other intentional multi-VLAN gateway unless the nodes really have L2 interfaces in both VLANs. Avahi handles mDNS only; SSDP needs separate multicast policy.

The cluster-wide Cilium policy already notes that host-network pods are not treated as namespace pods. [Cilium policy](../../envs/network/main.jsonnet#L73-L87). Consequently, the NixOS/VLAN firewall—not a normal namespace NetworkPolicy—must be the primary isolation boundary for HA.

### Three realistic target states

| State | Placement | What survives failure of the USB node? | Pairing/migration risk |
|---|---|---|---|
| **Initial, recommended** | HA Container + ZHA pinned to the ZBDongle-E node | Neither HA nor Zigbee automatically moves, although the PVC remains recoverable | Lowest: same ZHA, same radio, official HA/ZHA backup path |
| **Decoupled using current USB** | HA may run on either local node; Zigbee2MQTT remains pinned with the dongle; MQTT is independent | HA and non-Zigbee automations can continue; Zigbee is unavailable until that node returns | Higher: ZHA→Z2M has code-level backup compatibility but no supported end-to-end migration; HA entity IDs/automations also need validation |
| **Best eventual topology** | HA on either local node; separate Z2M + MQTT; wired Ethernet coordinator | HA is independent of a Kubernetes node; Zigbee still depends on one coordinator and one Z2M writer | Coordinator migration can be staged, but ZHA→Z2M remains an explicitly tested project |

If the only goal is **HA node failover**, an officially supported ZHA radio migration to a suitable wired coordinator is the lower-risk next step: HA can restart on either node and reconnect to the coordinator. If the goal is **keeping the Zigbee network process alive while HA restarts/upgrades**, Z2M provides real value because ZHA cannot be externalized. Those are different goals.

### Concrete staged rollout

1. **Prove restore before Kubernetes:** make a full encrypted HA backup and a manual ZHA network backup; retain the emergency-kit key off the HA OS machine.
2. **Deploy the smallest destination:** one explicit-version HA Container StatefulSet, one `longhorn-v1` `/config` claim, 60-second-or-longer termination grace, host network plus `ClusterFirstWithHostNet`, Traefik Service/route, the dedicated coordinator-node label, and only the stable `/dev/serial/by-id/...` device path.
3. **Fix and test the LAN boundary:** add scoped NixOS multicast firewall rules, establish router-side mDNS reflection where required, establish separate SSDP handling, and test both VLANs from the chosen node. Host network alone is not acceptance evidence.
4. **Cold cutover:** final backup, power down HA OS, move the physical dongle, restore HA, point ZHA at its new path, and verify every paired device before changing any Zigbee stack.
5. **Replace each former HA OS app independently:** deploy only the apps actually in use as their own Kubernetes workloads and reconnect their HA integrations. An HA backup does not create these pods.
6. **Exercise recovery:** restore to a fresh PVC/namespace and document how to return the radio and workload to service. Keep application backups off Longhorn as well as storage snapshots, especially because this repository records prior Longhorn failure incidents.
7. **Only then choose the future Zigbee branch:** migrate ZHA to a wired coordinator if node mobility is enough, or lab-test ZHA→Z2M with rollback if independent Zigbee lifecycle is worth the additional migration risk.

## Decision record

| Decision | Recommendation | Reason |
|---|---|---|
| Initial HA platform | Official HA Container in Kubernetes, one StatefulSet/PVC | Feasible while keeping the deployment surface small; HA OS is not replicated in Kubernetes. |
| HA availability | One writer; restart/restore target, not active-active | SQLite/config/integration/coordinator state and USB ownership are single-writer concerns. |
| Initial Zigbee | Keep ZHA and the existing ZBDongle-E | Official ZHA backup/reconfigure path; avoids compounding migration risk. |
| USB placement | Node pin + stable by-id device mapping | The coordinator is physically node-bound. |
| Discovery | Host network initially, then measured VLAN policy | Compatible with HA's LAN discovery, but multicast/VLAN behavior remains network-owned. |
| Future Zigbee decoupling | Separate Z2M + MQTT + wired Ethernet coordinator, after a lab migration | Removes HA USB affinity; Z2M first-party docs prefer wired Ethernet over Wi-Fi. |
| ZHA→Z2M | Experimental staged migration only | Shared backup format/code supports the idea, but no supported end-user procedure exists. |
| Community operator | Evaluate later, not baseline | Active and documented, but physical-device/network features are explicitly alpha/unproven. |
