# Netmaker

Netmaker Pro server, UI, and MQTT use the official Netmaker HA Helm chart. The
Kubernetes Operator uses its official chart. `labsonnet.libsonnet` is used only
for the single Remote Access Gateway netclient workload.

## Endpoints

- Public API / Netmaker Desktop server: `https://vpn.dzerv.art`
- Admin-only dashboard: `https://dashboard.vpn.dzerv.art`
- Public MQTT-over-WebSocket broker: `wss://broker.vpn.dzerv.art`
- Private applications: `*.vpn.dzerv.art`
- WireGuard gateway: public WAN address, UDP `51821`

The server and UI each run two replicas with PodDisruptionBudgets and preferred
cross-node spreading. MQTT remains single-replica because Netmaker's upstream HA
configuration does not support multiple broker replicas.

PostgreSQL is provided by a dedicated two-instance CloudNativePG cluster in the
`netmaker` namespace. There is no bundled or shared PostgreSQL workload.

`envs/headscale` currently also publishes `vpn.dzerv.art`. Do not deploy both
routes simultaneously; remove or disable the Headscale route before cutting the
entry hostname over to Netmaker.

## Required 1Password item

Create one item named `netmaker` with these fields:

| Field | Purpose |
| --- | --- |
| `master-key` | Long random Netmaker master key |
| `mq-password` | Long random MQTT password |
| `enrollment-token` | Enrollment token for the single network |

`enrollment-token` cannot be populated until the server is running and the
network exists. The gateway and every ingress proxy wait for it; the server can
start with `master-key` and `mq-password` first.

The token must be **unlimited-use and non-expiring**: the operator gives each
ingress proxy pod an `emptyDir` for `/etc/netclient`. Container restarts keep
that volume, so a crash-looping netclient reuses its identity, but any event that
replaces the *pod* (eviction, node drain or upgrade, manual delete) enrols a
brand new Netmaker host. Only the gateway StatefulSet has a PVC, so only it
keeps a stable identity across rescheduling.

Stale hosts are not reaped automatically. Netmaker's zombie collector
(`logic/zombie.go`, every 6h) only quarantines a host when a new record shares an
existing `HostID` or `MacAddress`; a recreated pod has both a fresh host ID and a
fresh CNI MAC, so it never matches. Prune `*-ingress-proxy` hosts by hand, or
with `DELETE /api/v1/hosts/bulk` (body `{"ids": [...]}`).

## How access control works

Netmaker Pro enforces access with user groups and resource policies, so this
environment uses **one network** and controls per-service access in Netmaker
itself. The earlier two-network split was an OSS workaround and is gone.

The operator has **no CRDs for users, groups, services or ACLs**. Its only CRD,
`NetmakerOps`, is an unmodified kubebuilder scaffold (`spec.foo`, empty
reconciler) and is never instantiated. Everything below is manual server-side
state that cannot be reproduced from this repo — treat the dashboard as the
source of truth and keep this table in sync by hand.

| Service | DNS name | Allowed groups |
| --- | --- | --- |
| `netmaker-admin-ingress` (Traefik) | `*.vpn.dzerv.art` | `admin` |
| `netmaker-kube-api-ingress` | `kube.vpn.dzerv.art` | `admin` |
| `netmaker-cliproxyapi-ingress` | `ai.vpn.dzerv.art` | `admin`, `guest` |

`netmaker-admin-ingress` is only a name; it carries no privilege of its own.
Access is decided entirely by the Netmaker resource policies above.

## Bootstrap

1. Port-forward `service/netmaker-ui` for initial setup and create a single
   network. After the VPN works, use `https://dashboard.vpn.dzerv.art` instead.
2. Create an unlimited-use enrollment token for that network and store it as
   `enrollment-token` on the `netmaker` 1Password item.
3. Forward public UDP `51821` to a Kubernetes node running Traefik. Traefik's
   `netmaker` listener routes it to the `netmaker-gateway` Service.
4. Once `netmaker-gateway` appears as a Netmaker host, set its public endpoint to
   the WAN address with port `51821`, disable dynamic endpoint changes, and
   promote it to a Remote Access Gateway. The operator never does this: it only
   builds per-Service ingress proxy pods and never promotes a host to a gateway.
5. Create the `admin` and `guest` user groups, and grant both Remote Access
   Client access through `netmaker-gateway`.
6. Add resource policies matching the table above, so `guest` reaches only
   `ai.vpn.dzerv.art` while `admin` reaches every ingress.
7. Add split-DNS records for each required `*.vpn.dzerv.art` application, or a
   wildcard record if supported, pointing at the Netmaker address assigned to
   `netmaker-admin-ingress`.

Netmaker Desktop users enter `https://vpn.dzerv.art`; it downloads the gateway
endpoint for them.

Netmaker ACLs, not network separation, are now the security boundary. The
cliproxyapi `NetworkPolicy` permits proxy traffic from the `netmaker` and
`cliproxyapi` namespaces.

## How the operator works

The operator is annotation-driven, not CRD-driven. Both real controllers watch
`Service` objects. For every Service annotated `netmaker.io/ingress: enabled` it
creates a `<service>-ingress-proxy` pod **in that Service's own namespace**,
owned by the Service, running `gravitl/netclient` plus an `alpine/socat`
container that forwards the pod's WireGuard IP to the Service's ClusterIP.

Ingress traffic therefore does **not** pass through the netclient sidecar in the
operator Deployment. That sidecar exists for the operator's own API proxy on
port `8085`, which overlaps with `netmaker-kube-api-ingress`; `proxyMode` is
`noauth`, meaning it adds no impersonation headers and callers still present
their own Kubernetes credentials.

## Upstream defects patched in the overlay

These are worked around in `main.jsonnet` rather than in the vendored charts:

- **CoreDNS cannot read its Corefile.** The chart mounts the shared RWX volume
  with no `fsGroup`, but `coredns/coredns` runs as UID 65532 while Netmaker
  writes the Corefile as root, and a Longhorn RWX export root is
  `drwx------ root root`. `fsGroup` cannot fix this because Longhorn's CSIDriver
  uses the default `ReadWriteOnceWithFSType` policy, so Kubernetes skips
  ownership management on RWX volumes. The container runs as root instead;
  share-manager does not squash root.
- **Operator ClusterRole omits Secrets.** The controllers read Secrets in
  arbitrary namespaces, but upstream has no `kubebuilder:rbac` marker for
  `secrets`, so the manager fails its Secret watch. The overlay appends
  cluster-wide `get`/`list`/`watch`.
- **`OPERATOR_NAMESPACE` is never set.** The binary defaults it to
  `netmaker-k8s-ops-system`. Token lookup tries the Service's namespace first
  and then `OPERATOR_NAMESPACE`; our proxy Services live in `traefik`,
  `cliproxyapi` and `default` while `netmaker-op` lives in `netmaker`, so both
  lookups missed and every proxy pod received `TOKEN=""`. The overlay sets it
  from `metadata.namespace`. Because cross-namespace `secretKeyRef` is
  impossible, the operator then inlines the token as a literal `value:` in each
  proxy pod spec; mirror `netmaker-op` into those namespaces instead if that
  exposure matters.

## Notes

- The operator runs in `noauth` mode because API-backed user synchronisation
  requires a Netmaker Pro API token.
- The single `netmaker-op` External Secret supplies server, gateway and operator
  credentials.
- The gateway UDP route does not create a Netmaker Remote Access Gateway by
  itself; the `netmaker-gateway` host must be promoted in the dashboard.
- The Kubernetes API ingress uses an `ExternalName` alias for
  `kubernetes.default.svc.cluster.local` instead of hard-coding a ClusterIP.
- Server docs: <https://docs.netmaker.io/docs/server-installation/ha-installation-on-k8s>
- Operator docs: <https://learn.netmaker.io/kubernetes-operator>
- Operator source: <https://github.com/gravitl/netmaker-k8s-ops>
