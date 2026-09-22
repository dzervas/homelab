local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);
local opsecretLib = import 'docker-service/opsecret.libsonnet';

local namespace = 'external-dns';
local domain = 'dzerv.art';

{
  namespace: k.core.v1.namespace.new(namespace),

  // Publishes an A record per internet-reachable node, so a node going
  // NotReady/cordoned drops out of DNS (--exclude-unschedulable, on by default).
  externalDns: helm.template('external-dns', '../../charts/external-dns', {
    namespace: namespace,
    values: {
      sources: ['node'],
      // The homelab nodes only have RFC1918 addresses, which the node source
      // would happily publish as public A records.
      labelFilter: 'topology.kubernetes.io/zone in (oracle,grnet)',

      provider: { name: 'cloudflare' },
      // Not a targeting rule - it only stops external-dns from touching any
      // other zone the Cloudflare token can reach. The per-node records
      // (gr0/fra0/fra1) are protected by TXT ownership, not by this.
      domainFilters: [domain],
      policy: 'sync',
      txtOwnerId: 'homelab',
      // The apex holds the MX/SPF/verification TXT records, so keep the
      // ownership registry off it. Managing an apex needs the record type
      // substituted into the prefix and the prefix ending in a period:
      // otherwise the registry builds 'a-dzerv.art', a sibling domain that
      // matches no hosted zone, and the ownership record is skipped.
      txtPrefix: '_edns-%{record_type}.',

      // React to node condition changes instead of waiting out the interval
      interval: '30s',
      triggerLoopOnEvent: true,

      env: [{
        name: 'CF_API_TOKEN',
        valueFrom: {
          secretKeyRef: {
            name: 'cert-manager-op',
            key: 'cloudflare-api-token',
          },
        },
      }],

      extraArgs: [
        // Every matching node templates to the apex, so their IPs end up as one RRset
        '--fqdn-template=' + domain,
        // Cloudflare record comments are metadata only - never served in DNS responses
        '--cloudflare-record-comment=managed by external-dns (envs/external-dns)',
        // The node source emits TTL 0, which Cloudflare would turn into its
        // 300s default - too slow to fail a dead node out of the RRset.
        '--min-ttl=60s',
      ],

      serviceMonitor: { enabled: true },
    },
  }),

  // 1Password external secret for the Cloudflare API token
  externalDnsOp: opsecretLib.new('cert-manager'),
}
