local client = import './cache-client.libsonnet';
local cilium = import 'cilium-libsonnet/1.18/main.libsonnet';
local externalSecrets = import 'external-secrets.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local lab = import 'labsonnet.libsonnet';

local ciliumNetworkPolicy = cilium.cilium.v2.ciliumNetworkPolicy;
local clusterSecretStore = externalSecrets.nogroup.v1.clusterSecretStore;
local externalSecret = externalSecrets.nogroup.v1.externalSecret;

local namespace = 'forgejo';
local jobNamespace = 'forgejo-runners';
local externalSecretsNamespace = 'external-secrets';
local runnerImage = 'data.forgejo.org/forgejo/runner:13';
local secretName = 'forgejo-runner';
local runnerId = 'c0ffee00f0f9e7a1';
local cachePort = 4001;
local signingStore = 'forgejo-cache-signing';
local traefikSelector = { 'k8s:io.kubernetes.pod.namespace': 'traefik', 'app.kubernetes.io/name': 'traefik' };
local jobSelector = { 'k8s:io.kubernetes.pod.namespace': jobNamespace };

{
  // Keep this exact generator/Secret identity when the deprecated runner is removed
  // Changing its name/template/refresh policy could rotate the existing cache signing key
  forgejoRunnerSecret:
    externalSecret.new(secretName)
    + externalSecret.spec.target.template.withData({
      token: runnerId + '{{ .password | sha1sum | trunc 24 }}',
      'cache-secret': '{{ .password | sha256sum }}',
    })
    + externalSecret.spec.withRefreshPolicy('OnChange')
    + externalSecret.spec.withDataFrom([{
      sourceRef: {
        generatorRef: {
          apiVersion: 'generators.external-secrets.io/v1alpha1',
          kind: 'ClusterGenerator',
          name: 'password',
        },
      },
    }]),

  // StatefulSet, Service, claim template and labels retain their pre-migration identities
  forgejoRunnerCache:
    lab.new('forgejo-runner-cache', runnerImage)
    + lab.withNamespace(namespace)
    + lab.withType('StatefulSet')
    // CoreDNS maps *.vpn.dzerv.art to Traefik; its existing public wildcard cert covers this host
    // No magicentry filter or path rewrite: cache requests and archive URLs retain their paths
    + lab.withVpnHttp(cachePort, 'forgejo-cache.vpn.dzerv.art', ['10.200.0.0/16'], name='http')
    + lab.withPV('/data', { name: 'data', size: '20Gi', storageClassName: 'longhorn-throwaway' })
    + lab.withEnv({ TZ: timezone })
    + lab.withSecretEnv({ CACHE_SECRET: { name: secretName, key: 'cache-secret' } })
    + lab.withArgs([
      'forgejo-runner',
      'cache-server',
      '--dir=/data',
      '--port=%d' % cachePort,
      '--secret=$(CACHE_SECRET)',
    ]),

  // remoteRef.property mirrors only cache-secret; it never regenerates the source password
  // Provider SA's get/resourceNames permits the WHOLE source Secret, including registration token
  // Kubernetes RBAC is not property-level; job SAs are never granted this provider SA's access
  cacheSigningStore:
    clusterSecretStore.new(signingStore)
    + clusterSecretStore.spec.withConditions([{ namespaces: [jobNamespace] }])
    + {
      spec+: {
        provider: {
          kubernetes: {
            remoteNamespace: namespace,
            server: {
              caProvider: {
                type: 'ConfigMap',
                name: 'kube-root-ca.crt',
                key: 'ca.crt',
                namespace: externalSecretsNamespace,
              },
            },
            auth: {
              serviceAccount: {
                name: signingStore,
                namespace: externalSecretsNamespace,
              },
            },
          },
        },
      },
    },

  cacheSigningServiceAccount:
    k.core.v1.serviceAccount.new(signingStore)
    + k.core.v1.serviceAccount.metadata.withNamespace(externalSecretsNamespace),

  cacheSigningRole:
    k.rbac.v1.role.new(signingStore)
    + k.rbac.v1.role.metadata.withNamespace(namespace)
    + k.rbac.v1.role.withRules([
      {
        apiGroups: [''],
        resources: ['secrets'],
        resourceNames: [secretName],
        verbs: ['get'],
      },
      {
        apiGroups: ['authorization.k8s.io'],
        resources: ['selfsubjectrulesreviews'],
        verbs: ['create'],
      },
    ]),

  cacheSigningRoleBinding:
    k.rbac.v1.roleBinding.new(signingStore)
    + k.rbac.v1.roleBinding.metadata.withNamespace(namespace)
    + k.rbac.v1.roleBinding.roleRef.withApiGroup('rbac.authorization.k8s.io')
    + k.rbac.v1.roleBinding.roleRef.withKind('Role')
    + k.rbac.v1.roleBinding.roleRef.withName(signingStore)
    + k.rbac.v1.roleBinding.withSubjects([{
      kind: 'ServiceAccount',
      name: signingStore,
      namespace: externalSecretsNamespace,
    }]),

  cacheSigningMirror:
    externalSecret.new(client.secretName)
    + externalSecret.metadata.withNamespace(jobNamespace)
    + externalSecret.spec.withRefreshInterval('1h')
    + externalSecret.spec.secretStoreRef.withName(signingStore)
    + externalSecret.spec.secretStoreRef.withKind('ClusterSecretStore')
    + externalSecret.spec.withData([{
      secretKey: client.secretKey,
      remoteRef: { key: secretName, property: 'cache-secret' },
    }]),

  cacheBackendPolicy:
    ciliumNetworkPolicy.new('forgejo-cache-backend')
    + ciliumNetworkPolicy.metadata.withNamespace(namespace)
    + ciliumNetworkPolicy.spec.endpointSelector.withMatchLabels({ app: 'forgejo-runner-cache' })
    + ciliumNetworkPolicy.spec.withIngress([{
      fromEndpoints: [{ matchLabels: traefikSelector }],
      toPorts: [{ ports: [{ port: '%d' % cachePort, protocol: 'TCP' }] }],
    }])
    // Deny takes precedence over additive namespace grants; legacy same-namespace Sysbox remains unchanged
    + ciliumNetworkPolicy.spec.withIngressDeny([{
      fromEndpoints: [{ matchLabels: jobSelector }],
      toPorts: [{ ports: [{ port: '%d' % cachePort, protocol: 'TCP' }] }],
    }]),

  cacheGatewayIngress:
    ciliumNetworkPolicy.new('forgejo-cache-client')
    + ciliumNetworkPolicy.metadata.withNamespace('traefik')
    + ciliumNetworkPolicy.spec.endpointSelector.withMatchLabels({ 'app.kubernetes.io/name': 'traefik' })
    + ciliumNetworkPolicy.spec.withIngress([{
      fromEndpoints: [{ matchLabels: jobSelector }],
      toPorts: [{ ports: [{ port: '10443', protocol: 'TCP' }] }],
    }]),

  // v13.2 sends HMAC metadata, not the key, but has no MAC expiry: native proxy traffic must use TLS
  // https://code.forgejo.org/forgejo/runner/src/tag/v13.2.0/act/artifactcache/mac.go
  // Live gate: cold/fresh-Pod restore, concurrent owners, cross-repo isolation, restart and Docker credential isolation
}
