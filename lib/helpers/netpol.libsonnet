local cilium = import 'cilium-libsonnet/1.18/main.libsonnet';

local cnp = cilium.cilium.v2.ciliumNetworkPolicy;
local eg = cnp.spec.egress;

local nsKey = 'k8s:io.kubernetes.pod.namespace';

local ports(list) = eg.toPorts.withPorts([
  eg.toPorts.ports.withPort(std.toString(p.port)) + eg.toPorts.ports.withProtocol(std.get(p, 'protocol', 'TCP'))
  for p in list
]);

// Anything outside the cluster, pod/service/node CIDRs and the VPNs
local internet = {
  cidr: '0.0.0.0/0',
  except: ['10.0.0.0/8', '100.64.0.0/10', '127.0.0.0/8', '169.254.0.0/16', '172.16.0.0/12', '192.168.0.0/16'],
};

{
  internet:: internet,

  // Traefik's pods behind the *.vpn.dzerv.art ClusterIP. toFQDNs never matches
  // in-cluster IPs, and this opens every VPN vhost, not just one
  traefikVpn:: { namespace: 'traefik', labels: { 'app.kubernetes.io/name': 'traefik' }, ports: [{ port: 10443 }] },

  // Egress default-deny for the selected pods, plus what's listed:
  //   dns: allow kube-dns, restricted to dnsNames (default: cluster.local + fqdns; ['*'] = any)
  //   services: [{ namespace, name, ports }], endpoints: [{ namespace, labels, ports }]
  //   fqdns: [{ name } | { pattern }] on 443, cidrs: [{ cidr, except, ports? }]
  //   entities: [{ entities: ['host', …], ports? }]
  egress(name, namespace, selector, opts={})::
    local o = { dns: true, dnsNames: null, apiserver: false, services: [], endpoints: [], fqdns: [], cidrs: [], entities: [] } + opts;
    local dnsNames =
      if o.dnsNames != null then o.dnsNames
      else ['**.cluster.local'] + [std.get(f, 'name', std.get(f, 'pattern')) for f in o.fqdns];
    cnp.new(name)
    + cnp.metadata.withNamespace(namespace)
    + cnp.spec.endpointSelector.withMatchLabels(selector)
    + cnp.spec.enableDefaultDeny.withEgress(true)
    + cnp.spec.withEgress(
      (if o.dns then [
         eg.withToEndpoints([{ matchLabels: { [nsKey]: 'kube-system', 'k8s:k8s-app': 'kube-dns' } }])
         + eg.withToPorts([
           ports([{ port: 53, protocol: 'ANY' }])
           + eg.toPorts.rules.withDns([eg.toPorts.rules.dns.withMatchPattern(p) for p in dnsNames]),
         ]),
       ] else [])
      + (if o.apiserver then [eg.withToEntities(['kube-apiserver'])] else [])
      + [
        eg.withToServices([eg.toServices.k8sService.withNamespace(s.namespace) + eg.toServices.k8sService.withServiceName(s.name)])
        + (if std.objectHas(s, 'ports') then eg.withToPorts([ports(s.ports)]) else {})
        for s in o.services
      ]
      + [
        eg.withToEndpoints([{ matchLabels: { [nsKey]: e.namespace } + e.labels }])
        + (if std.objectHas(e, 'ports') then eg.withToPorts([ports(e.ports)]) else {})
        for e in o.endpoints
      ]
      // toFQDNs must be alone in its rule
      + (if o.fqdns != [] then [
           eg.withToFQDNs([
             if std.objectHas(f, 'name') then eg.toFQDNs.withMatchName(f.name) else eg.toFQDNs.withMatchPattern(f.pattern)
             for f in o.fqdns
           ])
           + eg.withToPorts([ports([{ port: 443 }])]),
         ] else [])
      + [
        eg.withToCIDRSet([eg.toCIDRSet.withCidr(c.cidr) + eg.toCIDRSet.withExcept(std.get(c, 'except', []))])
        + (if std.objectHas(c, 'ports') then eg.withToPorts([ports(c.ports)]) else {})
        for c in o.cidrs
      ]
      + [
        eg.withToEntities(e.entities)
        + (if std.objectHas(e, 'ports') then eg.withToPorts([ports(e.ports)]) else {})
        for e in o.entities
      ]
    ),

  // Deny ingress from pods outside the given namespaces. Deny rules win over
  // any allow, including envs/network's clusterwide one. NotIn alone would also
  // match identities without a namespace label (host, so kubelet probes), hence
  // the Exists
  onlyFromNamespaces(name, namespace, selector, namespaces, additionalIngress=[])::
    cnp.new(name)
    + cnp.metadata.withNamespace(namespace)
    + cnp.spec.endpointSelector.withMatchLabels(selector)
    + cnp.spec.enableDefaultDeny.withIngress(true)
    + cnp.spec.withIngress(
      (if namespaces == [] then [] else [{ fromEndpoints: [{ matchExpressions: [{ key: nsKey, operator: 'In', values: namespaces }] }] }])
      + additionalIngress
    ),
}
