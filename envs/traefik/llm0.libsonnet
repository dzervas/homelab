local cilium = import 'cilium-libsonnet/1.18/main.libsonnet';
local k = import 'k.libsonnet';

local service = k.core.v1.service;
local servicePort = k.core.v1.servicePort;
local endpointSlice = k.discovery.v1.endpointSlice;
local endpoint = k.discovery.v1.endpoint;
local endpointPort = k.discovery.v1.endpointPort;
local egressGatewayPolicy = cilium.cilium.v2.ciliumEgressGatewayPolicy;

local name = 'llm0';
local domain = 'llm0.dzerv.art';
// llm0's LAN address (nixos/hosts/llm0.nix), a standalone box outside the cluster
local address = '10.13.37.130';

// llm0's caddy terminates TLS and gets its own certificate (nixos/inference/caddy.nix)
{
  llm0: {
    // Selectorless, so the endpointslice controller leaves the manual slice alone
    service:
      service.newWithoutSelector(name)
      + service.spec.withPorts([servicePort.newNamed('https', 443, 443)]),

    endpointSlice:
      endpointSlice.new(name)
      + endpointSlice.metadata.withLabels({
        'kubernetes.io/service-name': name,
        'endpointslice.kubernetes.io/managed-by': 'tanka',
      })
      + endpointSlice.withAddressType('IPv4')
      // Traefik drops endpoints without an explicit ready condition (crd/kubernetes_tcp.go)
      + endpointSlice.withEndpoints([endpoint.withAddresses([address]) + endpoint.conditions.withReady(true)])
      + endpointSlice.withPorts([endpointPort.withName('https') + endpointPort.withPort(443) + endpointPort.withProtocol('TCP')]),

    // Only home nodes can reach the LAN: the cloud nodes route just the wg0 node IPs. Traefik pods
    // tunnel there and leave SNATed to the gateway's default-route address. With several matches
    // Cilium uses the first node by name (srv0), with no failover if it goes down
    egressGatewayPolicy:
      egressGatewayPolicy.new(name)
      + egressGatewayPolicy.spec.withSelectors([{
        podSelector: { matchLabels: {
          'io.kubernetes.pod.namespace': 'traefik',
          'app.kubernetes.io/name': 'traefik',
        } },
      }])
      + egressGatewayPolicy.spec.withDestinationCIDRs(['%s/32' % address])
      + egressGatewayPolicy.spec.egressGateway.nodeSelector.withMatchLabels({ provider: 'homelab' }),

    ingressRouteTcp: {
      apiVersion: 'traefik.io/v1alpha1',
      kind: 'IngressRouteTCP',
      metadata: { name: name },
      spec: {
        entryPoints: ['websecure'],
        routes: [{
          match: 'HostSNI(`%s`)' % domain,
          services: [{ name: name, port: 443 }],
        }],
        tls: { passthrough: true },
      },
    },
  },
}
