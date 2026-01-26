local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local k = import 'k.libsonnet';
local helm = tk.helm.new(std.thisFile);
local externalSecrets = import 'external-secrets-libsonnet/0.19/main.libsonnet';

local clusterSecretStore = externalSecrets.nogroup.v1.clusterSecretStore;
local clusterExternalSecret = externalSecrets.nogroup.v1.clusterExternalSecret;
local clusterGenerator = externalSecrets.generators.v1alpha1.clusterGenerator;

local namespace = 'external-secrets';

{
  // Helm release for external-secrets operator
  // For updates: https://github.com/external-secrets/external-secrets/releases
  externalSecrets: helm.template('external-secrets', '../../charts/external-secrets', {
    namespace: namespace,
    values: {
      serviceMonitor: { enabled: true },
      grafanaDashboard: { enabled: true },
      // Limit concurrent reconciliations to reduce API pressure
      concurrent: 1,
    },
  }),

  // ClusterGenerator for password generation
  passwordGenerator:
    clusterGenerator.new('password')
    + clusterGenerator.spec.withKind('Password')
    + clusterGenerator.spec.generator.passwordSpec.withLength(42)
    + clusterGenerator.spec.generator.passwordSpec.withSymbolCharacters('-_,.')
    + clusterGenerator.spec.generator.passwordSpec.withAllowRepeat(true),

  // ClusterSecretStore for 1Password SDK
  // Requires Service Account credentials:
  // 1password.com > developer tools > Infrastructure Secrets Management > Other > Create a Service Account
  // Save the token to op
  // k create secret generic onepasswordsdk-sa-token --namespace external-secrets --from-literal=token=(op item get --vault Private "<name>" --fields credential --reveal)
  onePasswordStore:
    clusterSecretStore.new('1password')
    + {
      spec+: {
        // Reduce retry aggressiveness to avoid hitting 1Password rate limits
        retrySettings: {
          maxRetries: 24,
          retryInterval: '5m',
        },
        provider: {
          onepasswordSDK: {
            vault: 'k8s-secrets',
            auth: {
              serviceAccountSecretRef: {
                namespace: namespace,
                name: 'onepasswordsdk-sa-token',
                key: 'token',
              },
            },
          },
        },
      },
    },

  // ClusterExternalSecret for cluster-wide GHCR access
  ghcrClusterSecret:
    clusterExternalSecret.new('ghcr-cluster-secret')
    + clusterExternalSecret.spec.withExternalSecretName('ghcr-cluster-secret')
    + clusterExternalSecret.spec.withNamespaceSelectors([
      { matchLabels: { ghcrCreds: 'enabled' } },
    ])
    + clusterExternalSecret.spec.externalSecretSpec.withRefreshInterval('1h')
    + clusterExternalSecret.spec.externalSecretSpec.secretStoreRef.withName('1password')
    + clusterExternalSecret.spec.externalSecretSpec.secretStoreRef.withKind('ClusterSecretStore')
    + clusterExternalSecret.spec.externalSecretSpec.target.withName('ghcr-cluster-secret')
    + clusterExternalSecret.spec.externalSecretSpec.target.withCreationPolicy('Owner')
    + clusterExternalSecret.spec.externalSecretSpec.target.template.withType('kubernetes.io/dockerconfigjson')
    + clusterExternalSecret.spec.externalSecretSpec.target.template.withData({
      '.dockerconfigjson': std.manifestJsonEx({
        auths: {
          'ghcr.io': {
            username: '{{ .ghcr_username }}',
            password: '{{ .ghcr_token }}',
          },
        },
      }, '', ''),
    })
    + clusterExternalSecret.spec.externalSecretSpec.withDataFrom([
      { extract: { key: 'external-secrets' } },
    ]),

  // NetworkPolicy to allow access to external-secrets webhook from tf/kubectl/etc.
  webhookNetworkPolicy:
    k.networking.v1.networkPolicy.new('allow-external-secrets-webhook')
    + k.networking.v1.networkPolicy.metadata.withNamespace(namespace)
    + k.networking.v1.networkPolicy.spec.podSelector.withMatchLabels({
      'app.kubernetes.io/name': 'external-secrets-webhook',
    })
    + k.networking.v1.networkPolicy.spec.withPolicyTypes(['Ingress'])
    + k.networking.v1.networkPolicy.spec.withIngress([{
      from: [{
        ipBlock: {
          cidr: '0.0.0.0/0',
        },
      }],
      ports: [{
        protocol: 'TCP',
        port: 10250,  // Webhook port
      }],
    }]),
}
