local externalSecrets = import 'external-secrets-libsonnet/0.19/main.libsonnet';
local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local ingress = import 'helpers/ingress.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local externalSecret = externalSecrets.nogroup.v1.externalSecret;
local networkPolicy = k.networking.v1.networkPolicy;

local helm = tk.helm.new(std.thisFile);

{
  namespace:
    k.core.v1.namespace.new('magicentry')
    + k.core.v1.namespace.metadata.withLabels({ ghcrCreds: 'enabled' }),

  magicentry: helm.template('magicentry', '../../charts/magicentry', {
    namespace: $.namespace.metadata.name,
    values: {
      image: {
        repository: 'ghcr.io/dzervas/magicentry',
        tag: 'latest-kube',
      },

      ingress: ingress.hostObj('auth.dzerv.art'),
      persistence: {
        enabled: true,
        size: '1Gi',
      },

      config: {
        title: 'DZerv.Art Auth Service',
        request_enable: false,
        smtp_enable: true,
        smtp_from: 'DZerv.Art Auth Service <noreply@dzerv.art>',
        smtp_body: 'Click the link to login: <a href="{magic_link}">Login</a>',

        external_url: 'https://auth.dzerv.art',

        auth_url_user_header: 'X-Remote-User',
        auth_url_realms_header: 'X-Remote-Group',

        users_file: '/tmp/users.yaml',
      },

      extraConfigMapMounts: [{
        name: 'users',
        configMapName: 'users',
        mountPath: '/tmp/users.yaml',
        subPath: 'users.yaml',
      }],

      envSecrets: [{
        name: 'SMTP_URL',
        secretName: 'magicentry-secrets-op',
        secretKey: 'smtp_url',
      }],
    },
  }) + { pod_magicentry_test_connection: {} },

  secret:
    externalSecret.new('magicentry-secrets-op')
    + externalSecret.spec.secretStoreRef.withKind('ClusterSecretStore')
    + externalSecret.spec.secretStoreRef.withName('1password')
    + externalSecret.spec.withDataFrom([{ extract: { key: 'magicentry' } }])
    + externalSecret.spec.target.template.withData({
      smtp_url: 'smtp://noreply%40dzerv.art:{{ .smtp_password }}@smtp.office365.com:587/?tls=required',
    }),

  networkPolicy:
    networkPolicy.new('allow-magicentry')
    + networkPolicy.spec.podSelector.withMatchLabels({ 'app.kubernetes.io/name': 'magicentry' })
    + networkPolicy.spec.withPolicyTypes(['Ingress'])
    + networkPolicy.spec.withIngress([{
      from: [
        {
          namespaceSelector: {},
          podSelector: { matchLabels: { 'magicentry.rs/enable': 'true' } },
        },
        {
          // Allow traefik for auth-url
          namespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': 'traefik' } },
        },
      ],
      ports: [{ port: 8080, protocol: 'TCP' }],
    }]),
}
