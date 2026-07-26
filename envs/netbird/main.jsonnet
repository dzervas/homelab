local opsecretLib = import 'docker-service/opsecret.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);

local server = import './server.libsonnet';

{
  namespace: k.core.v1.namespace.new('netbird'),

  operator:
    helm.template('netbird-operator', '../../charts/netbird-operator', {
      namespace: $.namespace.metadata.name,
      values: {
        clusterSecretsPermissions: { allowAllSecrets: false },

        // cluster: {
        //   dns: 'svc.cluster.local',
        //   name: 'kubernetes',
        // },

        // Self-hosted control plane, see server.libsonnet
        managementURL: 'https://netbird.dzerv.art',
        netbirdAPI: { keyFromSecret: { name: 'netbird-op', key: 'api-key' } },
      },
    }),

  operatorOpSecret: opsecretLib.new('netbird'),

  router: {
    apiVersion: 'netbird.io/v1alpha1',
    kind: 'NetworkRouter',
    metadata: {
      name: 'internal',
    },
    spec: {
      dnsZoneRef: {
        name: 'vpn.dzerv.art',
      },
      // 3 replicas (the default) cannot spread over 2 usable nodes - avoidHomelab
      // rules out srv0, gr1 is cordoned and gr0 is full - so two pods always land
      // on the same node. The descheduler's RemoveDuplicates then evicts one every
      // 2 minutes, and every replacement pod registers a netbird peer that outlives
      // it, which is where the 200+ dead routing peers came from.
      workloadOverride: {
        replicas: 2,
      },
    },
  },

  // Register Traefik's ClusterIP in the router's DNS zone. The operator creates
  // traefik.traefik.vpn.dzerv.art -> the Service ClusterIP; the wildcard CNAME
  // in the NetBird zone points every *.vpn.dzerv.art name at this record.
  //
  // This resource must live beside the referenced Service because serviceRef
  // is namespace-local, even though the NetworkRouter is in netbird.
  traefikServiceResource: {
    apiVersion: 'netbird.io/v1alpha1',
    kind: 'NetworkResource',
    metadata: {
      name: 'traefik',
      namespace: 'traefik',
    },
    spec: {
      networkRouterRef: {
        name: 'internal',
        namespace: 'netbird',
      },
      serviceRef: { name: 'traefik' },
      groups: [{ name: 'kubernetes' }],
    },
  },

  // Route the whole *.vpn.dzerv.art wildcard through traefik so netbird peers
  // reach the same ingress as tailscale ones, TLS and middlewares included.
  // NetworkResource only takes a serviceRef, so the wildcard needs NBResource,
  // which accepts a raw address (wildcards allowed - see the domain regex in
  // shared/management/domain/validate.go).
  //
  // The wildcard does NOT match the apex, so vpn.dzerv.art itself is not covered.
  //
  // The routing peer resolves the name with its own resolver, i.e. CoreDNS, which
  // answers with the traefik ClusterIP - so peer traffic reaches traefik directly
  // and never uses the node IPs that dns-controller hands to headscale.
  traefikResource: {
    // the NB* CRDs are v1, unlike NetworkRouter/NetworkResource which are v1alpha1
    apiVersion: 'netbird.io/v1',
    kind: 'NBResource',
    metadata: {
      name: 'traefik',
    },
    spec: {
      name: 'traefik',
      address: '*.vpn.dzerv.art',
      // netbird's own network id, from `k -n netbird get networkrouter internal -o jsonpath='{.status.networkID}'`
      // NOT the NetworkRouter resource name
      networkID: 'd9in4gice66g009e2it0',
      groups: ['kubernetes'],
      tcpPorts: [443],
      // Binds this resource into the NBPolicy below. Without a policy netbird
      // distributes no route at all and peers just show `Networks: -`.
      policyName: 'traefik-vpn',
    },
  },

  // NBPolicy is a cluster-scoped policy *template*: it only carries the source
  // side, and each NBResource attaches its own destination and ports to it via
  // spec.policyName. Setting destinationGroups/ports here does nothing.
  traefikPolicy: {
    apiVersion: 'netbird.io/v1',
    kind: 'NBPolicy',
    metadata: {
      name: 'traefik-vpn',
    },
    spec: {
      name: 'traefik-vpn',
      sourceGroups: ['All'],
      protocols: ['tcp'],
    },
  },

  // Track the actual default/kubernetes Service rather than one control-plane
  // node or VIP. The operator follows Service.spec.clusterIP and creates:
  //   kubernetes.default.vpn.dzerv.art -> <current ClusterIP>
  // The stable kube.vpn.dzerv.art name should be an exact CNAME to that record;
  // it then overrides the *.vpn.dzerv.art Traefik wildcard without hardcoding
  // the Service IP. The API server certificate already includes kube.vpn.dzerv.art.
  //
  // This resource joins the same destination group used by traefik-vpn. The
  // policy's TCP/443 rule is kept alive by NBResource/traefik and therefore also
  // grants access to this dynamically tracked host resource.
  kubeApiServiceResource: {
    apiVersion: 'netbird.io/v1alpha1',
    kind: 'NetworkResource',
    metadata: {
      name: 'kube-api',
      namespace: 'default',
    },
    spec: {
      networkRouterRef: {
        name: 'internal',
        namespace: 'netbird',
      },
      serviceRef: { name: 'kubernetes' },
      groups: [{ name: 'kubernetes' }],
    },
  },
} + server
