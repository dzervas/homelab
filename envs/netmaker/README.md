# Netmaker

Netmaker OSS server, UI, and MQTT use the official Netmaker HA Helm chart. The
Kubernetes Operator uses its official chart. `labsonnet.libsonnet` is used only
for the two custom Remote Access Gateway netclient workloads.

## Endpoints

- Public API / Netmaker Desktop server: `https://vpn.dzerv.art`
- Admin-only dashboard: `https://dashboard.vpn.dzerv.art`
- Public MQTT-over-WebSocket broker: `wss://broker.vpn.dzerv.art`
- Private applications: `*.vpn.dzerv.art`
- Admin WireGuard gateway: public WAN address, UDP `51821`
- Restricted WireGuard gateway: public WAN address, UDP `51822`

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
| `admin-token` | Enrollment token for the `admin` network |
| `restricted-token` | Enrollment token for the `restricted` network |

The enrollment-token fields cannot be populated until the server is running and
the networks have been created. The operator waits for `admin-token`; the server
can start with `master-key` and `mq-password` first.

## OSS trust-tier bootstrap

Netmaker OSS has node ACLs but no Pro user-group/service ACLs. Isolation is
implemented with two separate networks and operator ingress proxies:

1. Port-forward `service/netmaker-ui` for initial setup and create networks named
   `admin` and `restricted`. After the admin VPN works, use
   `https://dashboard.vpn.dzerv.art` instead.
2. Create an enrollment token for each network and store them as `admin-token`
   and `restricted-token` on the `netmaker` 1Password item.
3. Forward public UDP `51821` and `51822` to a Kubernetes node running Traefik.
   Traefik's `netmaker-admin` and `netmaker-restricted` listeners route them to
   the corresponding gateway Service.
4. Once `netmaker-gateway-admin` and `netmaker-gateway-restricted` appear as
   Netmaker hosts, set their public endpoints to the WAN address with ports
   `51821` and `51822`, disable dynamic endpoint changes, and promote each host
   to a Remote Access Gateway for its matching network.
5. Give administrators Remote Access Client access only to `admin`. Give the
   restricted user access only to `restricted`. Netmaker Desktop users enter
   `https://vpn.dzerv.art`; it downloads the selected gateway endpoint for them.
6. In `admin`, allow clients to reach `netmaker-admin-ingress` and
   `netmaker-kube-api-ingress`. In `restricted`, allow clients to reach only
   `netmaker-cliproxyapi-ingress`.
7. Never add restricted clients or admin ingress proxies to the opposite network.

The restricted ingress asks the operator to register `ai.vpn.dzerv.art`. The
Kubernetes API ingress similarly registers `kube.vpn.dzerv.art`. In the admin
network, add split-DNS records for each required `*.vpn.dzerv.art` application,
or a wildcard record if supported, pointing to the Netmaker address assigned to
the admin Traefik ingress proxy.

Network separation, not DNS, is the security boundary. The cliproxyapi
`NetworkPolicy` permits proxy traffic from the `netmaker` and `cliproxyapi`
namespaces.

## Notes

- The operator runs in `noauth` mode because API-backed user synchronisation
  requires Netmaker Pro.
- The single `netmaker-op` External Secret supplies server and operator credentials.
- The gateway UDP routes do not create Netmaker Remote Access Gateways by
  themselves; the two netclient hosts must be promoted in the dashboard.
- The Kubernetes API ingress uses an `ExternalName` alias for
  `kubernetes.default.svc.cluster.local` instead of hard-coding a ClusterIP.
- Server docs: <https://docs.netmaker.io/docs/server-installation/ha-installation-on-k8s>
- Operator docs: <https://learn.netmaker.io/kubernetes-operator>
