local k = import 'k.libsonnet';
local lab = import 'labsonnet.libsonnet';

local networkPolicy = k.networking.v1.networkPolicy;

{
  cliproxyapi:
    lab.new('cliproxyapi', 'eceasy/cli-proxy-api')
    + lab.withType('StatefulSet')
    + lab.withArgs(['./CLIProxyAPI', '-config', '/data/config.yaml'])
    + lab.withPV('/data', { name: 'cliproxyapi', size: '128Mi' })
    + lab.withVpnHttp(8317, 'ai.vpn.dzerv.art')
    + lab.withOpEnvs({ MANAGEMENT_PASSWORD: 'password' }),

  networkPolicy:
    networkPolicy.new('allow-cliproxyapi')
    + networkPolicy.spec.podSelector.withMatchLabels({ 'app.kubernetes.io/name': 'cliproxyapi' })
    + networkPolicy.spec.withPolicyTypes(['Ingress'])
    + networkPolicy.spec.withIngress([{
      from: [{
        namespaceSelector: {},
        podSelector: { matchLabels: { 'ai/enable': 'true' } },
      }],
      ports: [{ port: 8317, protocol: 'TCP' }],
    }]),
}
