local externalSecrets = import 'external-secrets.libsonnet';
local netpol = import 'helpers/netpol.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local lab = import 'labsonnet.libsonnet';

local password = externalSecrets.generators.v1alpha1.password;
local externalSecret = externalSecrets.nogroup.v1.externalSecret;
local clusterSecretStore = externalSecrets.nogroup.v1.clusterSecretStore;
local serviceAccount = k.core.v1.serviceAccount;
local role = k.rbac.v1.role;
local roleBinding = k.rbac.v1.roleBinding;

local namespace = 'ntfy';
local domain = 'ntfy.vpn.dzerv.art';
local authReader = 'ntfy-hermes-auth-reader';
local users = [
  { name: 'dzervas', access: ['hermes:ro'] },
  // Hermes' adapter always subscribes; isolate that stream from outgoing notifications
  { name: 'hermes', access: ['hermes:wo', 'hermes-in:ro'] },
];

{
  // Upstream only lists third-party Helm charts: https://docs.ntfy.sh/install/#helm
  ntfy:
    lab.new('ntfy', 'binwiederhier/ntfy')
    + lab.withCreateNamespace()
    + lab.withType('StatefulSet')
    + lab.withArgs(['serve'])
    + lab.withPV('/var/lib/ntfy', { name: 'data', size: '1Gi' })
    + lab.withVpnHttp(8080, domain)
    + lab.withSecretEnv({
      ['NTFY_USER_%d' % i]: { name: 'ntfy-' + users[i].name + '-auth', key: 'user' }
      for i in std.range(0, std.length(users) - 1)
    } + {
      ['NTFY_TOKEN_%d' % i]: { name: 'ntfy-' + users[i].name + '-auth', key: 'auth-token' }
      for i in std.range(0, std.length(users) - 1)
    })
    // labsonnet puts secret envs first, so Kubernetes expands these references
    + lab.withEnv({
      NTFY_BASE_URL: 'https://' + domain,
      NTFY_LISTEN_HTTP: ':8080',
      NTFY_BEHIND_PROXY: 'true',
      NTFY_CACHE_FILE: '/var/lib/ntfy/cache.db',
      NTFY_AUTH_FILE: '/var/lib/ntfy/user.db',
      NTFY_AUTH_DEFAULT_ACCESS: 'deny-all',
      NTFY_AUTH_USERS: std.join(',', ['$(NTFY_USER_%d)' % i for i in std.range(0, std.length(users) - 1)]),
      NTFY_AUTH_TOKENS: std.join(',', ['$(NTFY_TOKEN_%d)' % i for i in std.range(0, std.length(users) - 1)]),
      NTFY_AUTH_ACCESS: std.join(',', [user.name + ':' + access for user in users for access in user.access]),
      NTFY_ENABLE_LOGIN: 'true',
      TZ: timezone,
    }),

  // ntfy requires tk_ plus exactly 29 alphanumeric characters
  tokenGenerator:
    password.new('ntfy-token')
    + password.spec.withLength(29)
    + password.spec.withSymbols(0)
    + password.spec.withAllowRepeat(true),

  auth: {
    [user.name]:
      externalSecret.new('ntfy-' + user.name + '-auth')
      // No automatic rotation: both ntfy and Hermes consume credentials at startup
      + externalSecret.spec.withRefreshPolicy('CreatedOnce')
      + externalSecret.spec.target.template.withEngineVersion('v2')
      + externalSecret.spec.target.template.withData({
        password: '{{ .password }}',
        token: 'tk_{{ .password }}',
        user: '%s:{{ .password | bcrypt }}:user' % user.name,
        'auth-token': '%s:tk_{{ .password }}:%s' % [user.name, user.name],
      })
      + externalSecret.spec.withDataFrom([{
        sourceRef: {
          generatorRef: {
            apiVersion: 'generators.external-secrets.io/v1alpha1',
            kind: 'Password',
            name: 'ntfy-token',
          },
        },
      }])
    for user in users
  },

  // ESO copies only Hermes' credential across namespaces; no access to the reader's token
  authReaderServiceAccount:
    serviceAccount.new(authReader)
    + serviceAccount.withAutomountServiceAccountToken(false),

  authReaderRole:
    role.new(authReader)
    + role.withRules([
      { apiGroups: [''], resources: ['secrets'], resourceNames: ['ntfy-hermes-auth'], verbs: ['get'] },
      { apiGroups: ['authorization.k8s.io'], resources: ['selfsubjectrulesreviews'], verbs: ['create'] },
    ]),

  authReaderRoleBinding:
    roleBinding.new(authReader)
    + roleBinding.roleRef.withApiGroup('rbac.authorization.k8s.io')
    + roleBinding.roleRef.withKind('Role')
    + roleBinding.roleRef.withName(authReader)
    + roleBinding.withSubjects([{ kind: 'ServiceAccount', name: authReader, namespace: namespace }]),

  authStore:
    clusterSecretStore.new('ntfy-hermes-auth')
    + { spec+: { conditions: [{ namespaces: ['hermes'] }] } }
    + clusterSecretStore.spec.provider.kubernetes.withRemoteNamespace(namespace)
    + clusterSecretStore.spec.provider.kubernetes.server.withUrl('https://kubernetes.default.svc')
    + clusterSecretStore.spec.provider.kubernetes.server.caProvider.withType('ConfigMap')
    + clusterSecretStore.spec.provider.kubernetes.server.caProvider.withName('kube-root-ca.crt')
    + clusterSecretStore.spec.provider.kubernetes.server.caProvider.withKey('ca.crt')
    + clusterSecretStore.spec.provider.kubernetes.server.caProvider.withNamespace(namespace)
    + clusterSecretStore.spec.provider.kubernetes.auth.serviceAccount.withName(authReader)
    + clusterSecretStore.spec.provider.kubernetes.auth.serviceAccount.withNamespace(namespace),

  ingress: netpol.onlyFromNamespaces('ntfy-ingress', namespace, { 'app.kubernetes.io/name': 'ntfy' }, ['traefik'], [
    {
      fromEndpoints: [{ matchLabels: { 'k8s:io.kubernetes.pod.namespace': 'hermes', 'app.kubernetes.io/name': 'hermes' } }],
      toPorts: [{ ports: [{ port: '8080', protocol: 'TCP' }] }],
    },
  ]),

  egress: netpol.egress('ntfy-egress', namespace, { 'app.kubernetes.io/name': 'ntfy' }, { dns: false }),
}
