// Where the agent's terminal, file tools and execute_code run, over SSH from
// the hermes pod. `agent` with sudo, internet egress, gVisor underneath: it's the
// part that's allowed to explode. Wipe the volume to reset it; Hermes' memory
// and the Signal account live in the hermes pod.
local externalSecrets = import 'external-secrets.libsonnet';
local netpol = import 'helpers/netpol.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local lab = import 'labsonnet.libsonnet';

local externalSecret = externalSecrets.nogroup.v1.externalSecret;

local namespace = 'hermes-workspace';

{
  // baseline, not restricted: root is allowed, privileged/hostPath still aren't
  namespace:
    k.core.v1.namespace.new(namespace)
    + k.core.v1.namespace.metadata.withLabels({
      'pod-security.kubernetes.io/enforce': 'baseline',
      'pod-security.kubernetes.io/enforce-version': 'latest',
    }),

  workspace:
    lab.new('workspace', 'git.vpn.dzerv.art/dzervas/homelab/hermes-workspace:latest')  // docker/hermes-workspace
    + lab.withNamespace(namespace)
    + lab.withType('StatefulSet')
    + lab.withPV('/home', { name: 'home', size: '20Gi' })
    + lab.withPort({ port: 22, name: 'ssh' })
    + lab.withSecretMount('/etc/workspace-ssh', 'workspace-ssh')
    // 1Password item hermes-workspace, field git-credentials:
    // https://<forgejo bot user>:<token>@git.vpn.dzerv.art (one per line)
    + lab.withExternalSecretEnvs('workspace-op', { GIT_CREDENTIALS: 'git-credentials' }, {
      store: '1password',
      remoteKey: 'hermes-workspace',
    })
    + lab.withEnv({ TZ: timezone })
    + lab.withResources({ requests: { cpu: '100m', memory: '512Mi' }, limits: { memory: '4Gi' } })
    // sshd starts as root with the default capability set; the agent logs in
    // as `agent` and escalates with sudo (setuid, hence allowPrivilegeEscalation)
    + lab.withSecurityContext({
      runAsNonRoot: false,
      runAsUser: 0,
      runAsGroup: 0,
      allowPrivilegeEscalation: true,
      capabilities: { drop: [] },
    })
    + lab.withPodSecurityContext({ runAsNonRoot: false, fsGroup: 0 })
    + {
      workload+: { spec+: { template+: { spec+: {
        runtimeClassName: 'gvisor',
        automountServiceAccountToken: false,
        securityContext+: { seccompProfile: { type: 'RuntimeDefault' } },
      } } } },
    },

  // Only Hermes' public key: the private one stays in the hermes namespace
  workspaceSsh:
    externalSecret.new('workspace-ssh')
    + externalSecret.metadata.withNamespace(namespace)
    + externalSecret.spec.secretStoreRef.withKind('ClusterSecretStore')
    + externalSecret.spec.secretStoreRef.withName('1password')
    // Resolve the SSH public key directly; bulk extraction supplies an empty value
    + externalSecret.spec.withData([{
      secretKey: 'authorized_keys',
      remoteRef: { key: 'hermes-workspace-ssh/public_key' },
    }]),

  egress: netpol.egress('workspace-egress', namespace, { 'app.kubernetes.io/name': 'workspace' }, {
    dnsNames: ['*'],
    cidrs: [netpol.internet],
    // git.vpn.dzerv.art (Forgejo) and other VPN vhosts
    endpoints: [netpol.traefikVpn],
  }),

  ingress: netpol.onlyFromNamespaces('workspace-ingress', namespace, { 'app.kubernetes.io/name': 'workspace' }, ['hermes']),
}
