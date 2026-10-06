// Hermes Workspace UI, separate from the SSH workspace agent
local affinity = import 'helpers/affinity.libsonnet';
local netpol = import 'helpers/netpol.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local lab = import 'labsonnet.libsonnet';

local namespace = 'hermes';
local domain = 'agent.vpn.dzerv.art';
local image = 'ghcr.io/outsourc-e/hermes-workspace:latest';

{
  ui:
    lab.new('workspace-ui', image)
    + lab.withNamespace(namespace)
    + lab.withType('StatefulSet')
    + lab.withRunAsUser(10010)  // Image's workspace user
    + lab.withPV('/workspace', { name: 'workspace', size: '20Gi' })
    + lab.withVpnHttp(3000, domain, magicentry={ name: 'Hermes Workspace', realms: 'admin' })
    + lab.withSecretEnv({ HERMES_API_TOKEN: { name: 'hermes-api-key', key: 'password' } })
    + lab.withAffinity(affinity.requireProviders(['homelab']))
    + lab.withEnv({
      TZ: timezone,
      HERMES_HOME: '/home/workspace/.hermes',
      HERMES_WORKSPACE_DIR: '/workspace',
      HERMES_API_URL: 'http://hermes.hermes.svc:8642',
      HERMES_DASHBOARD_URL: 'http://hermes.hermes.svc:9119',
      HERMES_ALLOW_INSECURE_REMOTE: '1',  // magicentry auth

      // Hermes home is not mounted here; keep UI-only state on its PVC
      HERMES_WORKSPACE_STATE_DIR: '/workspace/.hermes-workspace',
    })
    + {
      workload+: { spec+: { template+: { spec+: {
        runtimeClassName: 'gvisor',
        automountServiceAccountToken: false,
        securityContext+: { seccompProfile: { type: 'RuntimeDefault' } },
      } } } },
    },

  egress: netpol.egress('workspace-ui-egress', namespace, { 'app.kubernetes.io/name': 'workspace-ui' }, {
    endpoints: [{
      namespace: namespace,
      labels: { 'app.kubernetes.io/name': 'hermes' },
      ports: [{ port: 'gateway' }, { port: 'vpn-9119' }],
    }],
  }),

  ingress: netpol.onlyFromNamespaces('workspace-ui-ingress', namespace, { 'app.kubernetes.io/name': 'workspace-ui' }, ['traefik']),
}
