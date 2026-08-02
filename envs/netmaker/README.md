# Netmaker

Netmaker OSS is deployed with the upstream HA Helm chart and the Netmaker
Kubernetes Operator.

## Endpoints

- Dashboard / human entry point: `https://vpn.dzerv.art`
- API: `https://api.vpn.dzerv.art`
- MQTT-over-WebSocket broker: `wss://broker.vpn.dzerv.art`
- Private applications: `*.vpn.dzerv.art`

The server and UI each run two replicas with PodDisruptionBudgets and preferred
cross-node spreading. The upstream chart only supports one MQTT replica, so the
broker remains a single replica even though the stateless Netmaker control plane
is HA.

PostgreSQL is provided by the shared CloudNativePG cluster. The Netmaker chart's
built-in PostgreSQL is disabled.

`envs/headscale` currently also publishes `vpn.dzerv.art`. Do not deploy both
routes simultaneously; remove or disable the Headscale route before cutting the
entry hostname over to Netmaker.

## Required 1Password fields

Create an item named `netmaker` with these fields:

| Field | Purpose |
| --- | --- |
| `postgres-password` | Password used by the CloudNativePG `netmaker` role |
| `master-key` | Netmaker master key; generate a long random value |
| `mq-password` | MQTT password; generate a long random value |
| `admin-token` | Enrollment token for the `admin` network |
| `restricted-token` | Enrollment token for the `restricted` network |

`admin-token` and `restricted-token` cannot be populated until the server is
running and the networks have been created. Until then the operator waits for
its token Secrets, while the Netmaker server can start normally.

## OSS trust-tier bootstrap

Netmaker OSS has node ACLs but no Pro user-group/service ACLs. Isolation is
therefore implemented with two separate networks and two operator ingress
proxies:

1. Sign in at `https://vpn.dzerv.art` and create networks named `admin` and
   `restricted`.
2. Create an enrollment token for each network and store them in the 1Password
   fields listed above.
3. Give administrators Remote Access Client access only to `admin`. Give the
   restricted user access only to `restricted`.
4. In `admin`, allow the user's clients to reach the operator nodes created for:
   - `netmaker-admin-ingress` (Traefik and therefore the application wildcard)
   - `netmaker-kube-api-ingress` (the Kubernetes API)
5. In `restricted`, allow the user's clients to reach only the operator node
   created for `netmaker-cliproxyapi-ingress`.
6. Do not add the restricted user or client to `admin`, and do not add the admin
   ingress proxies to `restricted`.

The restricted ingress service asks the operator to register
`ai.vpn.dzerv.art`. The Kubernetes API ingress similarly registers
`kube.vpn.dzerv.art`. For the admin network, add split-DNS records for each
required `*.vpn.dzerv.art` application (or a wildcard record if supported by the
selected Netmaker DNS configuration) pointing to the Netmaker address assigned
to the admin Traefik ingress proxy.

This separation, not DNS, is the security boundary. The cliproxyapi
`NetworkPolicy` also permits proxy traffic originating from the `netmaker` or
`cliproxyapi` namespaces.

## Notes

- The operator runs in `noauth` mode because API-backed user synchronisation
  requires Netmaker Pro.
- The operator chart's generated placeholder token Secret is suppressed and
  replaced by External Secrets.
- The Kubernetes API `Service` is an `ExternalName` alias for
  `kubernetes.default.svc.cluster.local`; this avoids hard-coding the API
  Service ClusterIP.
- Netmaker server docs: <https://docs.netmaker.io/docs/server-installation/ha-installation-on-k8s>
- Operator docs: <https://learn.netmaker.io/kubernetes-operator>
