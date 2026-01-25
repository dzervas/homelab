local dockerService = import 'docker-service.libsonnet';
local ingress = import 'helpers/ingress.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';

local namespace = 'prowlarr';
local domain = 'dzerv.art';

local statefulSet = k.apps.v1.statefulSet;
local networkPolicy = k.networking.v1.networkPolicy;

{
  prowlarr: dockerService.new('prowlarr', 'ghcr.io/elfhosted/prowlarr-nightly:rolling', {
    fqdn: 'search.' + domain,
    ports: [9696],
    ingressAnnotations: ingress.mtlsAnnotations(namespace),
    labels: {
      managed_by: 'terraform',
      service: 'prowlarr',
    },
    pvs: {
      '/config': {
        name: 'config',
        size: '512Mi',
      },
    },
    env: {
      TZ: timezone,
    },
  }) + {
    // Add node selector to the statefulset
    workload+: statefulSet.spec.template.spec.withNodeSelector({ 'kubernetes.io/arch': 'amd64' }),
  },

  flaresolverr: dockerService.new('flaresolverr', 'ghcr.io/flaresolverr/flaresolverr', {
    namespace: namespace,
    type: 'Deployment',
    ports: [8191],
    ingressEnabled: false,
    labels: {
      managed_by: 'terraform',
      service: 'flaresolverr',
    },
    env: {
      TZ: timezone,
      // PROMETHEUS_ENABLED: 'true',
      // PROMETHEUS_PORT: '9191',
    },
  }),

  audiobookshelfAccessNetworkPolicy:
    networkPolicy.new('audiobookshelf-access')
    + networkPolicy.metadata.withNamespace(namespace)
    + networkPolicy.spec.podSelector.withMatchLabels({})
    + networkPolicy.spec.withPolicyTypes(['Ingress'])
    + networkPolicy.spec.withIngress([
      {
        from: [
          {
            namespaceSelector: {
              matchLabels: {
                'kubernetes.io/metadata.name': 'audiobookshelf',
              },
            },
          },
        ],
      },
    ]),
}
