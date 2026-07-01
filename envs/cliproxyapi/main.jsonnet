local k = import 'k.libsonnet';
local lab = import 'labsonnet.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';

local networkPolicy = k.networking.v1.networkPolicy;

{
  cliproxyapi:
    lab.new('cliproxyapi', 'eceasy/cli-proxy-api')
    + lab.withCreateNamespace()
    + lab.withType('StatefulSet')
    + lab.withArgs(['./CLIProxyAPI', '-config', '/data/config.yaml'])
    + lab.withPV('/data', { name: 'cliproxyapi', size: '128Mi' })
    + lab.withVpnHttp(8317, 'ai.vpn.dzerv.art')
    + lab.withOpEnvs({ MANAGEMENT_PASSWORD: 'password' }, 'cliproxyapi'),

  // Broken: Operation not permitted on /data
  // cpa_usage_keeper:
  //   lab.new('cpa-usage-keeper', 'ghcr.io/willxup/cpa-usage-keeper')
  //   + lab.withNamespace('cliproxyapi')
  //   + lab.withType('StatefulSet')
  //   + lab.withPV('/data', { name: 'cliproxyapi', size: '128Mi' })
  //   + lab.withOpEnvs({ CPA_MANAGEMENT_KEY: 'password' }, 'cliproxyapi')
  //   + lab.withVpnHttp(8080, 'ai-metrics.vpn.dzerv.art')
  //   + lab.withRunAsUser(100)
  //   + lab.withEnv({
  //     TZ: timezone,
  //     CPA_BASE_URL: 'http://cliproxyapi:8317',
  //     REDIS_QUEUE_ADDR: 'http://cliproxyapi:8317',
  //     AUTH_ENABLED: 'false',
  //     CPA_PUBLIC_URL: 'https://ai.vpn.dzerv.art'
  //   }),

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
