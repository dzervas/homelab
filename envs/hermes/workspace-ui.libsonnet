// Hermes Workspace UI, separate from the SSH workspace agent
local netpol = import 'helpers/netpol.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local lab = import 'labsonnet.libsonnet';

local namespace = 'hermes';
local domain = 'workspace.vpn.dzerv.art';
local image = 'ghcr.io/outsourc-e/hermes-workspace:latest';

{
  ui:
    lab.new('workspace-ui', image)
    + lab.withNamespace(namespace)
    + lab.withType('StatefulSet')
    + lab.withRunAsUser(10010)  // Image's workspace user
    + lab.withPV('/workspace', { name: 'workspace', size: '20Gi' })
    + lab.withPort({ port: 3000, name: 'http' })
    + lab.withVpnHttp(3000, domain)
    + lab.withPodLabels({ 'magicentry.rs/enable': 'true' })
    + lab.withEnv({
      TZ: timezone,
      HERMES_HOME: '/home/workspace/.hermes',
      HERMES_WORKSPACE_DIR: '/workspace',
      HERMES_API_URL: 'http://hermes.hermes.svc:8642',
      HERMES_DASHBOARD_URL: 'http://hermes.hermes.svc:9119',
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
      ports: [{ port: 8642 }, { port: 9119 }],
    }],
  }),

  ingress: netpol.onlyFromNamespaces('workspace-ui-ingress', namespace, { 'app.kubernetes.io/name': 'workspace-ui' }, ['traefik']),
}
