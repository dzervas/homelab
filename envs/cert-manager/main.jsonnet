local tk = import 'github.com/grafana/jsonnet-libs/tanka-util/main.libsonnet';
local helm = tk.helm.new(std.thisFile);
local k = import 'k.libsonnet';
local cm = import 'cert-manager-libsonnet/1.15/main.libsonnet';
local certificate = cm.nogroup.v1.certificate;
local opsecretLib = import 'docker-service/opsecret.libsonnet';

local issuers = import './issuers.libsonnet';
local pki = import './pki.libsonnet';
local pkiGlobal = import './pki-global.libsonnet';

local namespace = 'cert-manager';
local domain = 'dzerv.art';

{
  // Helm chart for cert-manager
  certManager: helm.template('cert-manager', '../../charts/cert-manager', {
    namespace: namespace,
    values: {
      crds: { enabled: true },
      prometheus: {
        servicemonitor: { enabled: true },
      },
      webhook: {
        networkPolicy: { enabled: true },
      },
      config: {
        featureGates: {
          // Disable the use of Exact PathType in Ingress resources, to work around a bug in ingress-nginx
          // https://github.com/kubernetes/ingress-nginx/issues/11176
          ACMEHTTP01IngressPathTypeExact: false,
        },
      },
      // Default ingress issuer
      ingressShim: {
        defaultIssuerKind: 'ClusterIssuer',
        defaultIssuerName: 'letsencrypt',
      },
    },
  }),

  // 1Password external secret for Cloudflare API token
  certManagerOp: opsecretLib.new('cert-manager'),

  // ClusterIssuers
  selfSignedIssuer: issuers.selfSigned,
  letsencryptIssuer: issuers.letsencrypt,

  // Headscale VPN certificate (stored in cert-manager namespace for shared access)
  headscaleVpnCert:
    certificate.new('headscale-vpn')
    + certificate.metadata.withNamespace(namespace)
    + certificate.spec.withSecretName('headscale-vpn-certificate')
    + certificate.spec.withDnsNames(['vpn.' + domain])
    + certificate.spec.issuerRef.withName('letsencrypt')
    + certificate.spec.issuerRef.withKind('ClusterIssuer'),

  // CiliumNetworkPolicy to allow webhook egress to kube-apiserver.
  // Standard NetworkPolicy ipBlock CIDR rules don't match Cilium's
  // reserved kube-apiserver identity, so we need an explicit entity allow.
  webhookApiserverEgress: {
    apiVersion: 'cilium.io/v2',
    kind: 'CiliumNetworkPolicy',
    metadata: {
      name: 'cert-manager-webhook-apiserver-egress',
      namespace: namespace,
    },
    spec: {
      endpointSelector: {
        matchLabels: {
          'app.kubernetes.io/component': 'webhook',
          'app.kubernetes.io/instance': 'cert-manager',
          'app.kubernetes.io/name': 'webhook',
        },
      },
      egress: [{
        toEntities: ['kube-apiserver'],
      }],
    },
  },
} + pki + pkiGlobal
