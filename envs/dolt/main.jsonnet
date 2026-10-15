local cm = import 'cert-manager-libsonnet/1.19/main.libsonnet';
local externalSecrets = import 'external-secrets.libsonnet';
local netpol = import 'helpers/netpol.libsonnet';
local timezone = import 'helpers/timezone.libsonnet';
local k = import 'k.libsonnet';
local lab = import 'labsonnet.libsonnet';

local certificate = cm.nogroup.v1.certificate;
local configMap = k.core.v1.configMap;
local externalSecret = externalSecrets.nogroup.v1.externalSecret;
local networkPolicy = k.networking.v1.networkPolicy;
local service = k.core.v1.service;

local domain = 'dolt.vpn.dzerv.art';

{
  dolt:
    // TODO: Auto-update?
    lab.new('dolt', 'dolthub/dolt-sql-server:2.5.0')
    + lab.withCreateNamespace()
    + lab.withNamespaceLabels({
      'pod-security.kubernetes.io/enforce': 'restricted',
      'pod-security.kubernetes.io/enforce-version': 'latest',
    })
    + lab.withType('StatefulSet')
    + lab.withPodSecurityContext({ seccompProfile: { type: 'RuntimeDefault' } })
    + lab.withServiceName('dolt')
    + lab.withPV('/var/lib/dolt', { name: 'data', size: '5Gi' })
    + lab.withPort({ port: 3306, name: 'mysql' })
    + lab.withConfigMapMount('/etc/dolt/servercfg.d', 'dolt-config')
    + lab.withSecretMount('/tls', 'dolt-tls')
    // The stock entrypoint provisions these on the first start; password rotation needs ALTER USER
    + lab.withSecretEnv({
      DOLT_ROOT_PASSWORD: { name: 'dolt-root', key: 'password' },
      DOLT_PASSWORD: { name: 'dolt-beads', key: 'password' },
    })
    + lab.withEnv({
      // Keep CLI configuration writable as labsonnet's non-root UID, on the persistent volume
      HOME: '/var/lib/dolt',
      DOLT_ROOT_HOST: 'localhost',
      DOLT_DATABASE: 'beads',
      DOLT_USER: 'beads',
      DOLT_USER_HOST: '%',
      TZ: timezone,
    })
    + {
      // Static VPN destination; see envs/wireguard/users.libsonnet and nixos/rke2/rke2-coredns-config.yaml
      service+: service.spec.withClusterIP('10.43.0.60'),
    },

  // Keep credentials static and independent of ExternalSecret deletion; back them up with the PVC
  // Never delete these Secrets while retaining Dolt data: missing Secrets would get new passwords
  passwords: {
    [name]:
      externalSecret.new(name)
      + externalSecret.spec.withRefreshPolicy('CreatedOnce')
      + externalSecret.spec.target.withCreationPolicy('Orphan')
      + externalSecret.spec.target.withImmutable(true)
      + externalSecret.spec.withDataFrom([{
        sourceRef: {
          generatorRef: {
            apiVersion: 'generators.external-secrets.io/v1alpha1',
            kind: 'ClusterGenerator',
            name: 'password',
          },
        },
      }])
    for name in ['dolt-root', 'dolt-beads']
  },

  config:
    configMap.new('dolt-config', {
      'config.yaml': std.manifestYamlDoc({
        listener: {
          host: '0.0.0.0',
          port: 3306,
          tls_cert: '/tls/tls.crt',
          tls_key: '/tls/tls.key',
          require_secure_transport: true,
        },
      }),
    }),

  // Dolt loads the certificate at startup; restart the StatefulSet after certificate renewal
  certificate:
    certificate.new('dolt')
    + certificate.spec.withSecretName('dolt-tls')
    + certificate.spec.withDnsNames([domain])
    + certificate.spec.issuerRef.withName('letsencrypt')
    + certificate.spec.issuerRef.withKind('ClusterIssuer'),

  // No outbound connections, including DNS; TLS issuance and password generation run in other pods
  egress: netpol.egress('dolt-egress', 'dolt', { 'app.kubernetes.io/name': 'dolt' }, { dns: false }),

  networkPolicy:
    networkPolicy.new('allow-dolt-vpn')
    + networkPolicy.spec.podSelector.withMatchLabels({ 'app.kubernetes.io/name': 'dolt' })
    + networkPolicy.spec.withPolicyTypes(['Ingress'])
    + networkPolicy.spec.withIngress([{
      from: [
        {
          namespaceSelector: { matchLabels: { 'kubernetes.io/metadata.name': 'wireguard' } },
          podSelector: { matchLabels: { app: 'wireguard', instance: 'users' } },
        },
        // Also allow admin peers if their source addresses are preserved rather than masqueraded
        { ipBlock: { cidr: '10.50.50.0/28' } },
      ],
      ports: [{ port: 3306, protocol: 'TCP' }],
    }]),
}
