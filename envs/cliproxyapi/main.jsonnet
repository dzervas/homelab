local dockerService = import 'docker-service.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local networkPolicy = k.networking.v1.networkPolicy;

{
  cliproxyapi: dockerService.new('cliproxyapi', 'eceasy/cli-proxy-api', {
    fqdn: 'ai.vpn.dzerv.art',
    ports: [8317],
    args: ['./CLIProxyAPI', '-config', '/data/config.yaml'],

    pvs: {
      '/data': {
        name: 'cliproxyapi',
        size: '128Mi',
      },
    },
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
