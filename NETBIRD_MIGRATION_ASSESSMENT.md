# Headscale to Self-hosted NetBird Migration Assessment

## Summary

Migrating from Headscale to self-hosted NetBird would be **moderate-to-hard** for this homelab, mostly because the current setup is not just Headscale. It is:

- Headscale in Kubernetes
- Tailscale clients on NixOS nodes
- A custom Kubernetes DNS controller
- Traefik VPN-only middleware
- nftables split ingress rules
- RKE2/node networking assumptions

Rough estimate:

| Scope | Estimate |
| --- | ---: |
| Basic self-hosted NetBird replacement | 1–2 days |
| Equivalent behavior to today | 3–5 days |
| Cleaner Kubernetes-native redesign with service/domain discovery | 1–2 weeks |

The biggest decision is whether to do a mostly-compatible migration or redesign around NetBird's Kubernetes-native model.

## Current setup

### Headscale

Defined in:

- `envs/headscale/main.jsonnet`

Current behavior:

- Headscale runs in-cluster.
- Public control-plane URL: `https://vpn.dzerv.art`
- Tailnet CIDR: `100.100.50.0/24`
- MagicDNS base domain: `ts.dzerv.art`
- Extra DNS records are loaded from `/data/dns.json`.

### Custom DNS controller

Defined in:

- `docker/dns-controller/main.py`

This is one of the most migration-sensitive pieces.

It watches Kubernetes:

- `Ingress`
- `HTTPRoute`
- `Pod`
- control-plane `Node`

Then it:

1. Calls the Headscale API.
2. Maps Kubernetes node name to Tailscale IPv4 address.
3. Finds the node currently running a backend pod for a given route/service.
4. Writes Headscale extra DNS records pointing ingress hostnames to that node's Tailscale IP.
5. Also writes `kube.vpn.dzerv.art`.

In other words, current service discovery is custom and dynamic:

```text
Ingress/HTTPRoute hostname -> node running backend pod -> node Tailscale IP
```

### Traefik VPN middleware

Defined in:

- `envs/traefik/middleware.libsonnet`

Current middleware:

```jsonnet
ipAllowList: {
  sourceRange: ['100.100.50.0/24'],
}
```

This is tied directly to the Headscale/Tailscale address range.

### VPN HTTP helper

Defined in:

- `lib/labsonnet.libsonnet`

`withVpnHttp(...)` attaches the `vpnonly` Traefik middleware to VPN-only services.

Many services use domains under:

```text
*.vpn.dzerv.art
```

### Host-level split ingress

Defined in:

- `nixos/rke2/firewall.nix`

Current nftables behavior:

```text
iifname tailscale0 tcp dport 80  -> 7080
iifname tailscale0 tcp dport 443 -> 7443
```

This means traffic arriving through the Tailscale interface is redirected to separate Traefik entrypoints.

### NixOS Tailscale setup

Defined in:

- `nixos/system/network.nix`

Current behavior:

- Tailscale is enabled on hosts.
- DNS and route acceptance are disabled:

```text
--accept-dns=false
--accept-routes=false
```

- Nodes advertise exit-node capability.
- There is a manual route for the Tailscale subnet.

## What NetBird improves

NetBird is likely better aligned with the desired direction: Kubernetes-native private service exposure and service/domain discovery.

Relevant NetBird capabilities:

- Self-hosted control plane
- Kubernetes operator
- `NetworkRouter` and `NetworkResource` CRDs
- Gateway API integration, currently beta / not fully feature-complete
- Custom DNS zones distributed to peers/groups
- Group/policy-based access control

The operator can expose Kubernetes services to NetBird by creating corresponding NetBird networks/resources and DNS records.

This could replace a lot of the current custom Headscale DNS-controller behavior if you adopt the NetBird model.

## What does not migrate cleanly

### 1. The DNS model is different

Today, the custom controller preserves existing ingress hostnames and maps them to node Tailscale IPs.

NetBird's native Kubernetes model is more like:

```text
Kubernetes Service -> NetworkResource -> routed private resource -> DNS record
```

Usually DNS becomes service/resource-oriented, for example:

```text
service.namespace.internal-zone
```

rather than automatically preserving every existing `*.vpn.dzerv.art` route hostname.

If exact hostname behavior must be preserved, you may still need either:

- a small custom controller using the NetBird API, or
- a repo-wide migration from `withVpnHttp(...)` to NetBird `NetworkResource` / Gateway API resources.

### 2. Traefik `vpnonly` needs rework

The current middleware allows only:

```text
100.100.50.0/24
```

With NetBird, Traefik may see different source IPs depending on the chosen design:

- NetBird peer IPs
- routing peer pod IPs
- node IPs
- NATed addresses
- NetBird resource/router addresses

So `vpnonly` cannot be blindly changed to another CIDR without testing.

Possible outcomes:

- update the allow-list to NetBird peer/resource ranges,
- allow only NetBird routing peers,
- or remove Traefik IP allow-listing and rely more heavily on NetBird policies.

### 3. nftables split ingress is Tailscale-specific

Current rules are bound to `tailscale0`.

With NetBird, you need to decide whether traffic reaches services through:

- host-level NetBird agents,
- Kubernetes routing peers,
- NetBird private resources,
- or Traefik as before.

If using host agents, equivalent interface-specific rules may be needed.

If using NetBird Kubernetes-native resources, the current host-level split ingress may become unnecessary or counterproductive.

### 4. ACL/policy migration is manual

Headscale currently has simple ACLs in `policies.hujson`.

NetBird is deny-by-default and uses groups/policies. The Kubernetes operator does not automatically create access policies.

You will need to explicitly model:

- personal devices,
- server nodes,
- routing peers,
- Kubernetes services,
- special users/devices such as `hass`,
- exit-node-like access, if still needed.

### 5. Self-hosted NetBird has more operational surface

Headscale is relatively small.

Self-hosted NetBird involves more pieces:

- management/server component,
- dashboard,
- signal/relay path,
- STUN/TURN,
- identity provider or embedded IdP,
- API tokens/service users,
- TLS/gRPC-compatible reverse proxy.

This is manageable, but it is more complex than Headscale.

## Migration options

## Option A: Minimal behavioral change

Keep Traefik as the private HTTP entrypoint and preserve most existing `*.vpn.dzerv.art` behavior.

Replace:

```text
Headscale extra DNS records
```

with either:

```text
NetBird DNS/API records
```

or a small NetBird-aware replacement for `docker/dns-controller`.

Pros:

- Less application churn.
- Keeps existing `*.vpn.dzerv.art` hostnames.
- Keeps current Traefik-based routing model.
- Easier rollback.

Cons:

- Still custom.
- Less Kubernetes-native.
- Does not fully exploit NetBird operator/resource model.

Difficulty: **medium**.

## Option B: NetBird-native Kubernetes access

Use NetBird's Kubernetes operator with:

- `NetworkRouter`
- `NetworkResource`
- possibly Gateway API integration where mature enough

Pros:

- Cleaner long-term model.
- Better Kubernetes-native service exposure.
- Less custom DNS/node-IP logic.
- Closer to the desired service/domain auto-discovery behavior.

Cons:

- Existing `withVpnHttp(...)` abstraction likely needs redesign.
- Some hostnames/access patterns may change.
- Traefik VPN middleware may become less central.
- Gateway API support should be treated carefully because it is still evolving.

Difficulty: **medium-hard**.

## Recommended migration path

Do **not** do a big-bang migration.

### Phase 1: Run NetBird beside Headscale

Deploy self-hosted NetBird at a separate hostname, for example:

```text
netbird.dzerv.art
```

Keep Headscale/Tailscale untouched.

Validate:

- login/authentication,
- peer enrollment,
- DNS behavior,
- NAT traversal,
- mobile/client support,
- basic policies.

### Phase 2: Join one laptop and one cluster-side peer

Add:

- one personal device,
- one Kubernetes node or NetBird routing peer.

Verify peer-to-peer connectivity before involving services.

### Phase 3: Expose one low-risk Kubernetes service

Pick a non-critical service using `withVpnHttp(...)`, such as a small internal web app.

Expose it using the NetBird operator and compare:

- DNS name,
- access control,
- latency,
- source IP seen by Traefik/app,
- whether `vpnonly` still works or becomes unnecessary.

### Phase 4: Decide target architecture

After the test service, decide whether to pursue:

1. compatibility-first migration, or
2. NetBird-native Kubernetes resources.

Do not migrate the rest until this decision is clear.

### Phase 5: Migrate policies and DNS

Create NetBird groups/policies for:

- personal/admin devices,
- servers,
- Kubernetes routing peers,
- special-purpose clients,
- private services.

Then migrate DNS/service exposure incrementally.

### Phase 6: Remove Headscale only after parity

Only remove Headscale once all of these are verified:

- all required devices are on NetBird,
- all private services are reachable,
- `*.vpn.dzerv.art` or replacement DNS works,
- Kubernetes API access works,
- Traefik private routes work or have been replaced,
- exit-node behavior is either migrated or intentionally dropped,
- firewall rules are updated,
- rollback is no longer needed.

## Key repo files to revisit

Likely affected files:

- `envs/headscale/main.jsonnet`
- `docker/dns-controller/main.py`
- `envs/traefik/middleware.libsonnet`
- `envs/traefik/main.jsonnet`
- `lib/labsonnet.libsonnet`
- `lib/helpers/ingress.libsonnet`
- `lib/docker-service/ingress.libsonnet`
- `nixos/system/network.nix`
- `nixos/rke2/firewall.nix`
- `nixos/rke2/config.nix`
- `nixos/rke2/default.nix`
- any service using `withVpnHttp(...)`

## Verdict

NetBird is probably a better fit for the desired Kubernetes-native service discovery direction.

But for this repo, it is **not a drop-in Headscale replacement**.

The difficult parts are:

1. replacing the custom Headscale DNS controller,
2. rethinking Traefik `vpnonly`,
3. reworking Tailscale-specific nftables split ingress,
4. migrating ACLs to NetBird groups/policies,
5. deciding whether `*.vpn.dzerv.art` remains Traefik-based or becomes NetBird resource DNS.

The safest approach is to run NetBird in parallel, migrate one service, and then choose between compatibility-first and NetBird-native designs.
