local lab = import 'labsonnet.libsonnet';

local namespace = 'n8n';

{
  // n8n-browserless deployment (headless browser for web scraping)
  // Uses dockerService like the original TF module
  n8nBrowserless:
    lab.new('n8n-browserless', 'ghcr.io/browserless/chromium')
    + lab.withNamespace(namespace)
    + lab.withVpnHttp(3000, 'browser.vpn.dzerv.art')
    + lab.withRunAsUser(999)  // BLESS_USER_ID env var
    + lab.withEnv({
      ALLOW_GET: 'true',  // Required for some stuff in the n8n node
      PROXY_HOST: 'n8n-browserless.' + namespace + '.svc.cluster.local',
      PROXY_PORT: '3000',
      PROXY_SSL: 'false',
      CONCURRENT: '5',
      QUEUED: '10',
      TIMEOUT: std.toString(15 * 60 * 1000),
    })
    + lab.withOpEnvs({ TOKEN: 'password' }, 'n8n-browserless')
    + lab.withAffinityPreferHomelab(),
}
