local dockerService = import 'docker-service.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local p = import 'prometheus-operator-libsonnet/0.83/main.libsonnet';
local networkPolicy = k.networking.v1.networkPolicy;

local exporterDef = dockerService.new('cliproxyapi-exporter', 'ghcr.io/dzervas/cliproxyapi-exporter', {
  namespace: 'cliproxyapi',
  ports: [9090],
});

{
  cliproxyapi: dockerService.new('cliproxyapi', 'eceasy/cli-proxy-api-plus', {
    fqdn: 'ai.vpn.dzerv.art',
    ports: [8317],
    args: ['./CLIProxyAPIPlus', '-config', '/data/config.yaml'],
    ingressAnnotations: {
      'nginx.ingress.kubernetes.io/proxy-body-size': '10m',
      'nginx.ingress.kubernetes.io/proxy-connect-timeout': '120',
      'nginx.ingress.kubernetes.io/proxy-read-timeout': '120',
      'nginx.ingress.kubernetes.io/proxy-send-timeout': '120',
    },

    op_envs: { MANAGEMENT_PASSWORD: 'password' },

    pvs: {
      '/data': {
        name: 'cliproxyapi',
        size: '128Mi',
      },
    },
  }) + { namespace: {} },

  exporter: exporterDef {
    workload+: k.apps.v1.deployment.spec.template.spec.withContainers(std.map(
      function(c)
        c + k.core.v1.container.withEnvMixin([{ name: 'CLIPROXYAPI_TOKEN', valueFrom: { secretKeyRef: { name: 'cliproxyapi-op', key: 'password' } } }]),
      exporterDef.workload.spec.template.spec.containers
    )),
  },

  exporterServiceScraper:
    p.monitoring.v1.serviceMonitor.new('cliproxyapi')
    + p.monitoring.v1.serviceMonitor.spec.withJobLabel('cliproxyapi')
    + p.monitoring.v1.serviceMonitor.spec.withEndpoints([
      p.monitoring.v1.serviceMonitor.spec.endpoints.withPort('docker-9090')
      + p.monitoring.v1.serviceMonitor.spec.endpoints.withPath('/metrics'),
    ])
    + p.monitoring.v1.serviceMonitor.spec.selector.withMatchLabels({
      app: 'cliproxyapi-exporter',
    }),

  networkPolicy:
    networkPolicy.new('allow-cliproxyapi')
    + networkPolicy.spec.podSelector.withMatchLabels({ 'app.kubernetes.io/name': 'cliproxyapi' })
    + networkPolicy.spec.withPolicyTypes(['Ingress'])
    + networkPolicy.spec.withIngress([{
      from: [{
        // For some reason VPN CIDR doesn't work
        namespaceSelector: {},
        podSelector: { matchLabels: { 'ai/enable': 'true' } },
      }],
      ports: [{ port: 8317, protocol: 'TCP' }],
    }]),
}
